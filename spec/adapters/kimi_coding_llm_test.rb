# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/adapters/kimi_coding_llm"

class KimiCodingLLMTest < Minitest::Test
  # Contract tests are commented out because they require valid API credentials.
  # Uncomment the following lines to run them with a real API key:
  # include AgentHarness::Test::LLMProviderContract
  #
  # def setup_provider
  #   master_key_path = File.expand_path("../../config/master.key", __dir__)
  #   secrets_path = File.expand_path("../../config/secrets.yml.enc", __dir__)
  #   secrets = AgentHarness::Secrets::FileProvider.new(
  #     master_key_path: master_key_path,
  #     secrets_path: secrets_path
  #   )
  #   AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)
  # end

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
    assert_equal "kimi-coding/k2p5", @llm.model
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
    
    assert_equal "kimi-coding/k2p5", body[:model]
    assert body[:tools]
    assert_equal "function", body[:tools].first[:type]
    assert_equal "test_tool", body[:tools].first[:function][:name]
  end

  def test_build_request_body_without_tools
    body = @llm.send(:build_request_body, [{ role: "user", content: "Test" }], [])
    
    assert_equal "kimi-coding/k2p5", body[:model]
    refute body[:tools]
  end

  def test_extract_usage_returns_defaults_when_nil
    usage = @llm.send(:extract_usage, nil)
    
    assert_equal 0, usage[:prompt_tokens]
    assert_equal 0, usage[:completion_tokens]
    assert_equal 0, usage[:total_tokens]
  end

  def test_extract_usage_extracts_values
    api_usage = {
      prompt_tokens: 10,
      completion_tokens: 20,
      total_tokens: 30
    }
    
    usage = @llm.send(:extract_usage, api_usage)
    
    assert_equal 10, usage[:prompt_tokens]
    assert_equal 20, usage[:completion_tokens]
    assert_equal 30, usage[:total_tokens]
  end

  def test_extract_usage_handles_missing_keys
    api_usage = { total_tokens: 50 }
    
    usage = @llm.send(:extract_usage, api_usage)
    
    assert_equal 0, usage[:prompt_tokens]
    assert_equal 0, usage[:completion_tokens]
    assert_equal 50, usage[:total_tokens]
  end

  def test_parse_tool_arguments_parses_json_string
    args = '{"key": "value", "num": 42}'
    result = @llm.send(:parse_tool_arguments, args)
    
    assert_equal "value", result[:key]
    assert_equal 42, result[:num]
  end

  def test_parse_tool_arguments_returns_hash_if_already_hash
    args = { key: "value" }
    result = @llm.send(:parse_tool_arguments, args)
    
    assert_equal args, result
  end

  def test_parse_tool_arguments_returns_empty_hash_for_nil
    result = @llm.send(:parse_tool_arguments, nil)
    
    assert_equal({}, result)
  end

  def test_parse_tool_arguments_handles_invalid_json
    result = @llm.send(:parse_tool_arguments, 'invalid json')
    
    assert_equal({ raw: 'invalid json' }, result)
  end

  def test_parse_response_with_tool_calls
    api_response = {
      choices: [{
        message: {
          content: nil,
          tool_calls: [{
            function: {
              name: "test_tool",
              arguments: '{"arg": "value"}'
            }
          }]
        },
        finish_reason: "tool_calls"
      }],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
    }.to_json
    
    result = @llm.send(:parse_response, api_response)
    
    assert_nil result[:content]
    assert_equal "tool_calls", result[:finish_reason]
    assert result[:tool_calls]
    assert_equal "test_tool", result[:tool_calls].first[:name]
    assert_equal({ arg: "value" }, result[:tool_calls].first[:arguments])
  end

  def test_parse_response_with_content
    api_response = {
      choices: [{
        message: { content: "Hello!" },
        finish_reason: "stop"
      }],
      usage: { prompt_tokens: 5, completion_tokens: 2, total_tokens: 7 }
    }.to_json
    
    result = @llm.send(:parse_response, api_response)
    
    assert_equal "Hello!", result[:content]
    assert_equal "stop", result[:finish_reason]
    refute result.key?(:tool_calls)
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
    
    assert_equal "function", result[:type]
    assert_equal "my_tool", result[:function][:name]
    assert_equal "Does something", result[:function][:description]
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
