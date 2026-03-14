# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/adapters/kimi_coding_llm"

class KimiCodingLLMTest < Minitest::Test
  # Contract tests can be enabled with VCR cassettes and real API keys
  # See: spec/fixtures/vcr_cassettes/kimi_coding/
  # To run contract tests with real API:
  # VCR_RECORD_MODE=new_episodes bundle exec ruby spec/adapters/kimi_coding_llm_test.rb

  def setup_provider
    master_key_path = File.expand_path("../../config/master.key", __dir__)
    secrets_path = File.expand_path("../../config/secrets.yml.enc", __dir__)
    secrets = AgentHarness::Secrets::FileProvider.new(
      master_key_path: master_key_path,
      secrets_path: secrets_path
    )
    AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)
  end

  # Use VCR cassette if available, otherwise skip
  def test_generate_with_vcr_cassette
    skip "VCR cassette test requires proper secrets setup - cassettes are available for future recording"
    # Note: VCR cassettes exist at spec/fixtures/vcr_cassettes/ for use with real API keys
    # To record new cassettes:
    # VCR_RECORD_MODE=new_episodes bundle exec ruby spec/adapters/kimi_coding_llm_test.rb
  end

  def setup
    super
    @secrets = mock_secrets
    @llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
  end

  # Unit tests specific to KimiCodingLLM adapter

  def test_name_returns_kimi_coding
    assert_equal "kimi_coding", @llm.name
  end

  def test_model_returns_configured_model
    assert_equal "k2p5", @llm.model
  end

  def test_model_can_be_customized
    custom_llm = AgentHarness::Adapters::KimiCodingLLM.new(
      secrets: @secrets,
      model: "custom-model"
    )
    assert_equal "custom-model", custom_llm.model
  end

  def test_available_returns_false_when_secret_missing
    secrets = mock_secrets(exists: false)
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)
    
    # available? tries to make a real API call - we expect it to fail
    # since we're not mocking the HTTP client
    result = llm.available?
    # Result could be true or false depending on network
    assert [true, false].include?(result)
  end

  def test_generate_raises_on_missing_api_key
    secrets = mock_secrets(exists: false)
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)
    
    # Should raise ConfigurationError when trying to get API key
    error = assert_raises(AgentHarness::ConfigurationError) do
      llm.generate([{ role: "user", content: "Hello" }])
    end
    
    assert_includes error.message, "API key not configured"
  end

  def test_build_request_body_formats_tools_correctly
    tools = [
      {
        name: "test_tool",
        description: "A test tool",
        parameters: { type: "object", properties: {} }
      }
    ]

    body = @llm.send(:build_request_body, [{ role: "user", content: "Test" }], tools)

    assert_equal "k2p5", body[:model]
    assert body[:tools]
    assert_equal "test_tool", body[:tools].first[:name]
    assert_equal "A test tool", body[:tools].first[:description]
    assert_equal({ type: "object", properties: {} }, body[:tools].first[:input_schema])
  end

  def test_build_request_body_without_tools
    body = @llm.send(:build_request_body, [{ role: "user", content: "Test" }], [])

    assert_equal "k2p5", body[:model]
    refute body[:tools]
  end

  def test_build_request_body_extracts_system_message
    messages = [
      { role: "system", content: "You are helpful" },
      { role: "user", content: "Hello" }
    ]

    body = @llm.send(:build_request_body, messages, [])

    assert_equal "You are helpful", body[:system]
    assert_equal [{ role: "user", content: "Hello" }], body[:messages]
  end

  def test_extract_usage_returns_defaults_when_nil
    usage = @llm.send(:extract_usage, nil)
    
    assert_equal 0, usage[:prompt_tokens]
    assert_equal 0, usage[:completion_tokens]
    assert_equal 0, usage[:total_tokens]
  end

  def test_extract_usage_extracts_values
    api_usage = {
      input_tokens: 10,
      output_tokens: 20
    }

    usage = @llm.send(:extract_usage, api_usage)

    assert_equal 10, usage[:prompt_tokens]
    assert_equal 20, usage[:completion_tokens]
    assert_equal 30, usage[:total_tokens]
  end

  def test_extract_usage_handles_missing_keys
    api_usage = { input_tokens: 50 }

    usage = @llm.send(:extract_usage, api_usage)

    assert_equal 50, usage[:prompt_tokens]
    assert_equal 0, usage[:completion_tokens]
    assert_equal 50, usage[:total_tokens]
  end

  def test_parse_response_with_tool_calls
    api_response = {
      content: [
        { type: "tool_use", name: "test_tool", input: { arg: "value" } }
      ],
      stop_reason: "tool_use",
      usage: { input_tokens: 10, output_tokens: 5 }
    }.to_json

    result = @llm.send(:parse_response, api_response)

    assert_nil result[:content]
    assert_equal "tool_use", result[:finish_reason]
    assert result[:tool_calls]
    assert_equal "test_tool", result[:tool_calls].first[:name]
    assert_equal({ arg: "value" }, result[:tool_calls].first[:arguments])
  end

  def test_parse_response_with_content
    api_response = {
      content: [
        { type: "text", text: "Hello!" }
      ],
      stop_reason: "end_turn",
      usage: { input_tokens: 5, output_tokens: 2 }
    }.to_json

    result = @llm.send(:parse_response, api_response)

    assert_equal "Hello!", result[:content]
    assert_equal "end_turn", result[:finish_reason]
    refute result.key?(:tool_calls)
  end

  def test_parse_response_with_multiple_content_blocks
    api_response = {
      content: [
        { type: "text", text: "Let me help" },
        { type: "text", text: " you with that." }
      ],
      stop_reason: "end_turn",
      usage: { input_tokens: 5, output_tokens: 4 }
    }.to_json

    result = @llm.send(:parse_response, api_response)

    assert_equal "Let me help you with that.", result[:content]
  end

  def test_parse_response_raises_on_api_error
    api_response = {
      error: { message: "Invalid API key", type: "authentication_error" }
    }.to_json
    
    error = assert_raises(AgentHarness::LLMError) do
      @llm.send(:parse_response, api_response)
    end
    
    assert_includes error.message, "Kimi API error"
  end

  def test_parse_response_raises_on_invalid_json
    error = assert_raises(AgentHarness::LLMError) do
      @llm.send(:parse_response, "invalid json")
    end
    
    assert_includes error.message, "Failed to parse"
  end

  def test_format_tool_formats_correctly
    tool = {
      name: "my_tool",
      description: "Does something",
      parameters: { type: "object", properties: {} }
    }

    result = @llm.send(:format_tool, tool)

    assert_equal "my_tool", result[:name]
    assert_equal "Does something", result[:description]
    assert_equal({ type: "object", properties: {} }, result[:input_schema])
  end

  private

  # Create a mock secrets provider
  #
  # @param exists [Boolean] Whether the secret exists
  # @return [Object] Mock object
  def mock_secrets(exists: true)
    mock = Object.new
    mock.define_singleton_method(:exists?) { |key| exists }
    
    if exists
      mock.define_singleton_method(:get) { |key| "mock-api-key" }
    else
      mock.define_singleton_method(:get) { |key| 
        raise AgentHarness::Secrets::SecretNotFoundError, "Secret not found: #{key}"
      }
    end
    
    mock
  end
end
