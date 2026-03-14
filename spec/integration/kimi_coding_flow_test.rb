# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../lib/adapters/kimi_coding_llm"

# Kimi Coding provider-specific integration tests
class KimiCodingFlowTest < AgentHarness::Test::IntegrationTest
  def setup
    super
    @secrets = mock_secrets
    @telegram_adapter = AgentHarness::Test::MockTelegramAdapter.new(
      bot_token: "test_token",
      allowlist: [81_540_425_16]
    )
  end

  # Test 1: Kimi with different models
  def test_kimi_with_custom_model
    stub_kimi_api(
      response_body: kimi_success_response(content: "Custom model response")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(
      secrets: @secrets,
      model: "kimi-k2.5"
    )

    assert_equal "kimi-k2.5", llm.model
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-kimi-custom",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello"))
    assert_equal 1, @telegram_adapter.sent_messages.length
  end

  # Test 2: Kimi tool calling flow
  def test_kimi_tool_calling
    stub_kimi_api(
      response_body: kimi_tool_response(
        tool_name: "get_weather",
        arguments: { location: "Hong Kong" }
      )
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    # Generate with tools
    response = llm.generate([
      { role: "user", content: "What's the weather in Hong Kong?" }
    ], tools: [
      {
        name: "get_weather",
        description: "Get weather for a location",
        parameters: {
          type: "object",
          properties: {
            location: { type: "string" }
          }
        }
      }
    ])

    # Should have tool calls in response
    assert response[:tool_calls]
    assert_equal "get_weather", response[:tool_calls].first[:name]
    assert_equal({ location: "Hong Kong" }, response[:tool_calls].first[:arguments])
    assert_nil response[:content]
    assert_equal "tool_use", response[:finish_reason]
  end

  # Test 3: Kimi with system prompt
  def test_kimi_with_system_prompt
    stub_kimi_api(
      response_body: kimi_success_response(content: "System prompt received")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-kimi-system",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm,
      config: { system_prompt: "You are a coding expert." }
    )

    harness.send(:process_message, test_message("Help me code"))
    
    # Verify message was processed
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "System prompt received", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 4: Kimi API returns 500 error
  def test_kimi_api_500_error
    stub_kimi_api(
      response_body: { error: { message: "Internal server error" } },
      status: 500
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-kimi-500",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello"))

    # Should send error message
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_includes @telegram_adapter.sent_messages.first[:text], "couldn't generate"
  end

  # Test 5: Kimi API rate limit
  def test_kimi_api_rate_limit
    stub_kimi_api(
      response_body: { error: { message: "Rate limit exceeded", type: "rate_limit_error" } },
      status: 429
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Hello" }])
    end
    
    assert_includes error.message, "Kimi API error"
  end

  # Test 6: Kimi with multi-turn conversation
  def test_kimi_multi_turn_conversation
    stub_kimi_api(
      response_body: kimi_success_response(content: "Second response")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    # Simulate multi-turn
    messages = [
      { role: "user", content: "First message" },
      { role: "assistant", content: "First response" },
      { role: "user", content: "Second message" }
    ]
    
    response = llm.generate(messages)
    
    assert_equal "Second response", response[:content]
    assert response[:usage]
    assert_equal 10, response[:usage][:prompt_tokens]
  end

  # Test 7: Kimi with empty tools array
  def test_kimi_empty_tools
    stub_kimi_api(
      response_body: kimi_success_response(content: "No tools needed")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    response = llm.generate(
      [{ role: "user", content: "Hello" }],
      tools: []
    )
    
    assert_equal "No tools needed", response[:content]
    assert_nil response[:tool_calls]
  end

  # Test 8: Kimi provider name and defaults
  def test_kimi_provider_metadata
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    assert_equal "kimi_coding", llm.name
    assert_equal "k2p5", llm.model
  end

  # Test 9: Kimi not available without API key
  def test_kimi_not_available_without_key
    empty_secrets = AgentHarness::Test::MockSecretsProvider.new({})
    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: empty_secrets)
    
    refute llm.available?(lightweight: true)
  end

  # Test 10: Kimi request body format verification
  def test_kimi_request_body_format
    stub_kimi_api(
      response_body: kimi_success_response(content: "OK")
    )

    llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: @secrets)
    
    # Build request body directly
    body = llm.send(:build_request_body, [
      { role: "system", content: "Be helpful" },
      { role: "user", content: "Hello" }
    ], [])
    
    # Anthropic format: system is separate, messages don't include system
    assert_equal "k2p5", body[:model]
    assert_equal "Be helpful", body[:system]
    assert_equal [{ role: "user", content: "Hello" }], body[:messages]
    assert body[:max_tokens]
  end
end
