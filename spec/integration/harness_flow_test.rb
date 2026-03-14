# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../lib/harness/harness"

# Main integration tests for the full Telegram → Harness → LLM → Response flow
class HarnessFlowTest < AgentHarness::Test::IntegrationTest
  def setup
    super
    @secrets = mock_secrets
    @telegram_adapter = AgentHarness::Test::MockTelegramAdapter.new(
      bot_token: "test_token",
      allowlist: [81_540_425_16]
    )
  end

  # Test 1: Full success flow with Kimi Coding provider
  def test_full_flow_with_kimi_coding
    # Stub the Kimi API
    stub_kimi_api(
      response_body: kimi_success_response(content: "Hello from Kimi!")
    )

    # Create LLM provider
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)

    # Create harness
    harness = AgentHarness::Harness.new(
      agent_id: "test-kimi-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm,
      config: { system_prompt: "You are a helpful assistant." }
    )

    # Process the message directly
    harness.send(:process_message, test_message("Hello, Kimi!"))

    # Verify response was sent
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Hello from Kimi!", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 2: Full success flow with OpenCode-go provider
  def test_full_flow_with_opencode_go
    # Stub the OpenCode-go API
    stub_opencode_api(
      response_body: opencode_success_response(content: "Hello from OpenCode-go!")
    )

    # Create LLM provider
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)

    # Create harness
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm,
      config: { system_prompt: "You are a helpful assistant." }
    )

    # Process the message
    harness.send(:process_message, test_message("Hello, OpenCode-go!"))

    # Verify response was sent
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Hello from OpenCode-go!", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 3: Error handling - LLM API returns error
  def test_handles_llm_api_error
    # Stub error response
    stub_kimi_api(
      response_body: api_error_response(message: "Invalid API key"),
      status: 401
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-error-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    # Process message - should handle error gracefully
    harness.send(:process_message, test_message("Hello"))

    # Should send error message to user
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_includes @telegram_adapter.sent_messages.first[:text], "couldn't generate"
  end

  # Test 4: Error handling - Network timeout
  def test_handles_network_timeout
    # Stub timeout
    stub_request(:post, "https://api.kimi.com/coding/v1/messages")
      .to_timeout

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-timeout-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    # Process message - should handle timeout
    harness.send(:process_message, test_message("Hello"))

    # Should send error message
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_includes @telegram_adapter.sent_messages.first[:text], "couldn't generate"
  end

  # Test 5: Multiple messages processed sequentially
  def test_multiple_messages_sequential
    stub_kimi_api(
      response_body: kimi_success_response(content: "Response 1")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-multi-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    # Process first message
    harness.send(:process_message, test_message("Message 1"))
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Response 1", @telegram_adapter.sent_messages.first[:text]

    # Stub next response
    stub_kimi_api(
      response_body: kimi_success_response(content: "Response 2")
    )

    # Process second message
    harness.send(:process_message, test_message("Message 2"))
    assert_equal 2, @telegram_adapter.sent_messages.length
    assert_equal "Response 2", @telegram_adapter.sent_messages.last[:text]
  end

  # Test 6: Long message handling
  def test_handles_long_messages
    long_text = "This is a very long message. " * 50
    
    stub_kimi_api(
      response_body: kimi_success_response(content: "Received your long message!")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-long-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message(long_text))

    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Received your long message!", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 7: Special characters in message
  def test_handles_special_characters
    special_text = "Hello! ñ, é, ü, 中文, 🎉, <b>HTML</b>, &amp; more"
    
    stub_opencode_api(
      response_body: opencode_success_response(content: "Got special chars!")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-special-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message(special_text))

    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Got special chars!", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 8: Empty response from LLM - harness sends error message
  def test_handles_empty_llm_response
    stub_kimi_api(
      response_body: {
        content: [],
        stop_reason: "end_turn",
        usage: { input_tokens: 5, output_tokens: 0 }
      }
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-empty-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello"))

    # When LLM returns empty content array, harness sends error message
    assert_equal 1, @telegram_adapter.sent_messages.length
    # Content is error message when LLM returns empty content
    assert_match(/couldn't generate|sorry|error/i, @telegram_adapter.sent_messages.first[:text])
  end

  # Test 9: Both providers available check
  def test_both_providers_available_check
    kimi_llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    opencode_llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)

    # Lightweight availability checks should work
    assert kimi_llm.available?(lightweight: true)
    assert opencode_llm.available?(lightweight: true)
  end

  # Test 10: Provider configuration errors
  def test_provider_missing_api_key
    bad_secrets = mock_secrets(
      "kimi_coding.api_key" => nil,
      "opencode_go.api_key" => nil
    )

    # Kimi should fail when trying to generate
    kimi_llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: bad_secrets)
    
    error = assert_raises(AgentHarness::ConfigurationError) do
      kimi_llm.generate([{ role: "user", content: "test" }])
    end
    assert_includes error.message, "API key not configured"

    # OpenCode-go should fail too
    opencode_llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: bad_secrets)
    
    error = assert_raises(AgentHarness::ConfigurationError) do
      opencode_llm.generate([{ role: "user", content: "test" }])
    end
    assert_includes error.message, "API key not configured"
  end
end
