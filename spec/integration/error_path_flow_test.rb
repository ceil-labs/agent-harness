# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../lib/harness/harness"
require_relative "../../lib/adapters/kimi_coding_llm"
require_relative "../../lib/adapters/opencode_go_llm"

# Integration tests for error paths
# Tests timeout, auth failures, send errors, and other failure scenarios
class ErrorPathFlowTest < AgentHarness::Test::IntegrationTest
  def setup
    super
    @secrets = mock_secrets
    @telegram_adapter = AgentHarness::Test::MockTelegramAdapter.new(
      bot_token: "test_token",
      allowlist: [81_540_425_16]
    )
  end

  # LLM timeout scenario - synchronous processing
  def test_llm_timeout_returns_error_message
    llm = AgentHarness::Test::MockLLMProvider.new(provider_type: :kimi_coding)
    llm.raise_error = true
    
    telegram = AgentHarness::Test::MockTelegramAdapter.new
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-timeout",
      input: telegram,
      output: telegram,
      llm: llm
    )
    
    message = TelegramFixtures.text_message(text: "Test timeout")
    harness.send(:process_message, standardize_fixture(message))
    
    assert_equal 1, telegram.sent_messages.length
    assert telegram.sent_messages.first[:text] || telegram.sent_messages.first[:caption]
    response_text = telegram.sent_messages.first[:text] || telegram.sent_messages.first[:caption]
    assert_match(/error|sorry|couldn't generate/i, response_text)
  end

  # LLM returns empty/nil response - synchronous processing
  def test_llm_empty_response_returns_error_message
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "Test empty" => { content: nil, usage: {}, finish_reason: "stop" }
      }
    )
    
    telegram = AgentHarness::Test::MockTelegramAdapter.new
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-empty",
      input: telegram,
      output: telegram,
      llm: llm
    )
    
    message = TelegramFixtures.text_message(text: "Test empty")
    harness.send(:process_message, standardize_fixture(message))
    
    assert_equal 1, telegram.sent_messages.length
    # When LLM returns nil content, harness sends error message
    response_text = telegram.sent_messages.first[:text] || telegram.sent_messages.first[:caption]
    assert_match(/couldn't generate|sorry|error/i, response_text)
  end

  # Kimi API authentication failure
  def test_kimi_auth_failure_raises_error
    stub_request(:post, "https://api.kimi.com/coding/v1/messages")
      .to_return(
        status: 401,
        body: { error: { message: "Invalid API key", type: "authentication_error" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_includes error.message, "Kimi API error"
  end

  # Kimi API server error (5xx)
  def test_kimi_server_error_raises_error
    stub_request(:post, "https://api.kimi.com/coding/v1/messages")
      .to_return(
        status: 503,
        body: { error: { message: "Service unavailable" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
  end

  # OpenCode-go API authentication failure
  def test_opencode_auth_failure_raises_error
    stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
      .to_return(
        status: 401,
        body: { error: { message: "Unauthorized", code: "invalid_api_key" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_includes error.message, "OpenCode-go API error"
  end

  # OpenCode-go API rate limiting
  def test_opencode_rate_limit_raises_error
    stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
      .to_return(
        status: 429,
        body: { error: { message: "Rate limit exceeded" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
  end

  # Telegram send message failure - synchronous
  def test_telegram_send_failure_handled
    telegram = AgentHarness::Test::MockTelegramAdapter.new
    
    # Override send to simulate failure
    def telegram.send(message, context: {})
      @sent_messages << { text: message, chat_id: context[:chat_id], failed: true }
      { success: false, message_id: nil, error: "Network error" }
    end
    
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "Test" => { content: "Response", usage: {}, finish_reason: "stop" }
      }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-send-fail",
      input: telegram,
      output: telegram,
      llm: llm
    )
    
    message = TelegramFixtures.text_message(text: "Test")
    harness.send(:process_message, standardize_fixture(message))
    
    # Message should have been attempted
    assert telegram.sent_messages.length > 0
  end

  # Invalid JSON response from Kimi API
  def test_kimi_invalid_json_response
    stub_request(:post, "https://api.kimi.com/coding/v1/messages")
      .to_return(
        status: 200,
        body: "not valid json",
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_match(/Failed to parse|non-JSON/i, error.message)
  end

  # Invalid JSON response from OpenCode-go API
  def test_opencode_invalid_json_response
    stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
      .to_return(
        status: 200,
        body: "not valid json",
        headers: { "Content-Type" => "application/json" }
      )
    
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    # OpenCode-go adapter has a different error message for non-JSON
    assert_includes error.message, "non-JSON response"
  end

  # Missing API key configuration
  def test_kimi_missing_api_key
    empty_secrets = AgentHarness::Test::MockSecretsProvider.new({})
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: empty_secrets)
    
    error = assert_raises(AgentHarness::ConfigurationError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_includes error.message, "API key not configured"
  end

  # Missing OpenCode-go API key
  def test_opencode_missing_api_key
    empty_secrets = AgentHarness::Test::MockSecretsProvider.new({})
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: empty_secrets)
    
    error = assert_raises(AgentHarness::ConfigurationError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_includes error.message, "API key not configured"
  end

  # Harness handles multiple errors - synchronous
  def test_concurrent_errors_handled
    telegram = AgentHarness::Test::MockTelegramAdapter.new
    llm = AgentHarness::Test::MockLLMProvider.new(provider_type: :kimi_coding)
    llm.raise_error = true
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-concurrent-errors",
      input: telegram,
      output: telegram,
      llm: llm
    )
    
    # Send multiple messages
    3.times do |i|
      message = TelegramFixtures.text_message(
        message_id: i + 1,
        text: "Message #{i + 1}"
      )
      harness.send(:process_message, standardize_fixture(message))
    end
    
    # All should get error responses
    assert_equal 3, telegram.sent_messages.length
    telegram.sent_messages.each do |sent|
      assert_includes sent[:text], "couldn't generate"
    end
  end

  # Network timeout simulation
  def test_network_timeout
    stub_request(:post, "https://api.kimi.com/coding/v1/messages")
      .to_timeout
    
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Test" }])
    end
    
    assert_match(/timeout|timed out/i, error.message)
  end

  # Empty messages array
  def test_empty_messages_array
    stub_kimi_api(response_body: {
      content: [{ type: "text", text: "OK" }],
      stop_reason: "end_turn",
      usage: {}
    })
    
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    result = llm.generate([])
    
    # Should handle gracefully
    assert result[:content]
  end

  # Non-ASCII characters in response
  def test_unicode_response_handling
    stub_opencode_api(response_body: {
      choices: [{
        message: { content: "Unicode: 🎉 中文 ñ é", role: "assistant" },
        finish_reason: "stop"
      }],
      usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 }
    })
    
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    result = llm.generate([{ role: "user", content: "Test" }])
    
    assert_includes result[:content], "🎉"
    assert_includes result[:content], "中文"
  end
  
  private
  
  def standardize_fixture(telegram_message)
    {
      id: telegram_message["message_id"].to_s,
      text: telegram_message["text"],
      chat_id: telegram_message["chat"]["id"],
      sender_id: telegram_message["from"]["id"],
      timestamp: Time.at(telegram_message["date"]).utc.iso8601,
      metadata: {}
    }
  end
end
