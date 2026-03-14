# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../lib/adapters/opencode_go_llm"

# OpenCode-go provider-specific integration tests
class OpenCodeGoFlowTest < AgentHarness::Test::IntegrationTest
  def setup
    super
    @secrets = mock_secrets
    @telegram_adapter = AgentHarness::Test::MockTelegramAdapter.new(
      bot_token: "test_token",
      allowlist: [81_540_425_16]
    )
  end

  # Test 1: OpenCode-go with GLM-5 model (default)
  def test_opencode_with_glm5_default
    stub_opencode_api(
      response_body: opencode_success_response(content: "GLM-5 response")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    assert_equal "glm-5", llm.model
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-glm5",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello GLM-5"))
    
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "GLM-5 response", @telegram_adapter.sent_messages.first[:text]
  end

  # Test 2: OpenCode-go with Kimi model
  def test_opencode_with_kimi_model
    stub_opencode_api(
      response_body: opencode_success_response(content: "Kimi via OpenCode-go")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(
      secrets: @secrets,
      model: "kimi-k2.5"
    )
    
    assert_equal "kimi-k2.5", llm.model
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-kimi",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello via OpenCode-go"))
    
    assert_equal 1, @telegram_adapter.sent_messages.length
  end

  # Test 3: OpenCode-go with MiniMax model
  def test_opencode_with_minimax_model
    stub_opencode_api(
      response_body: opencode_success_response(content: "MiniMax response")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(
      secrets: @secrets,
      model: "minimax-m2.5"
    )
    
    assert_equal "minimax-m2.5", llm.model
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-minimax",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello MiniMax"))
    
    assert_equal 1, @telegram_adapter.sent_messages.length
  end

  # Test 4: OpenCode-go tool calling flow
  def test_opencode_tool_calling
    stub_opencode_api(
      response_body: opencode_tool_response(
        tool_name: "search_web",
        arguments: { query: "Ruby programming" }
      )
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    response = llm.generate([
      { role: "user", content: "Search for Ruby programming" }
    ], tools: [
      {
        name: "search_web",
        description: "Search the web",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string" }
          }
        }
      }
    ])

    assert response[:tool_calls]
    assert_equal "search_web", response[:tool_calls].first[:name]
    assert_equal({ query: "Ruby programming" }, response[:tool_calls].first[:arguments])
    assert_nil response[:content]
    assert_equal "tool_calls", response[:finish_reason]
  end

  # Test 5: OpenCode-go API error handling
  def test_opencode_api_error
    stub_opencode_api(
      response_body: { error: { message: "Invalid API key", type: "authentication_error" } },
      status: 401
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Hello" }])
    end
    
    assert_includes error.message, "OpenCode-go API error"
  end

  # Test 6: OpenCode-go malformed JSON response
  def test_opencode_malformed_json
    stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
      .to_return(
        status: 200,
        body: "not valid json {",
        headers: { "Content-Type" => "application/json" }
      )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Hello" }])
    end
    
    assert_includes error.message, "non-JSON response"
  end

  # Test 7: OpenCode-go empty choices array
  def test_opencode_empty_choices
    stub_opencode_api(
      response_body: { choices: [], usage: { prompt_tokens: 0, completion_tokens: 0 } }
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    error = assert_raises(AgentHarness::LLMError) do
      llm.generate([{ role: "user", content: "Hello" }])
    end
    
    assert_includes error.message, "No choices"
  end

  # Test 8: OpenCode-go with system prompt preserved
  def test_opencode_system_prompt_preserved
    stub_opencode_api(
      response_body: opencode_success_response(content: "With system context")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-system",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm,
      config: { system_prompt: "You are a Ruby expert." }
    )

    harness.send(:process_message, test_message("Help me with Ruby"))
    
    assert_equal 1, @telegram_adapter.sent_messages.length
  end

  # Test 9: OpenCode-go request body format (OpenAI style)
  def test_opencode_request_body_format
    stub_opencode_api(
      response_body: opencode_success_response(content: "OK")
    )

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    # Build request body directly
    body = llm.send(:build_request_body, [
      { role: "system", content: "Be helpful" },
      { role: "user", content: "Hello" }
    ], [])
    
    # OpenAI format: system message stays in messages array
    assert_equal "glm-5", body[:model]
    assert_equal 2, body[:messages].length
    assert_equal "system", body[:messages][0][:role]
    assert_equal "Be helpful", body[:messages][0][:content]
    assert_equal "user", body[:messages][1][:role]
    assert body[:max_tokens]
  end

  # Test 10: OpenCode-go tool format (OpenAI function format)
  def test_opencode_tool_format
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    tool = {
      name: "my_tool",
      description: "Does something",
      parameters: { type: "object", properties: { arg: { type: "string" } } }
    }
    
    formatted = llm.send(:format_tool, tool)
    
    # OpenAI format
    assert_equal "function", formatted[:type]
    assert_equal "my_tool", formatted[:function][:name]
    assert_equal "Does something", formatted[:function][:description]
    assert formatted[:function][:parameters]
  end

  # Test 11: OpenCode-go timeout handling
  def test_opencode_timeout
    stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
      .to_timeout

    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    harness = AgentHarness::Harness.new(
      agent_id: "test-opencode-timeout",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )

    harness.send(:process_message, test_message("Hello"))

    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_includes @telegram_adapter.sent_messages.first[:text], "couldn't generate"
  end

  # Test 12: OpenCode-go provider metadata
  def test_opencode_provider_metadata
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    assert_equal "opencode_go", llm.name
    assert_equal "glm-5", llm.model
  end

  # Test 13: OpenCode-go not available without API key
  def test_opencode_not_available_without_key
    empty_secrets = AgentHarness::Test::MockSecretsProvider.new({})
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: empty_secrets)
    
    refute llm.available?(lightweight: true)
  end

  # Test 14: OpenCode-go usage extraction
  def test_opencode_usage_extraction
    llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: @secrets)
    
    # With all fields
    usage = llm.send(:extract_usage, {
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150
    })
    
    assert_equal 100, usage[:prompt_tokens]
    assert_equal 50, usage[:completion_tokens]
    assert_equal 150, usage[:total_tokens]
    
    # With missing fields
    usage = llm.send(:extract_usage, { prompt_tokens: 10 })
    assert_equal 10, usage[:prompt_tokens]
    assert_equal 0, usage[:completion_tokens]
    assert_equal 10, usage[:total_tokens]
  end
end
