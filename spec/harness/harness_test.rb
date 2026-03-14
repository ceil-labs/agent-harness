# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/harness/harness"

class HarnessTest < Minitest::Test
  def setup
    @input = SimpleMockInputAdapter.new
    @output = SimpleMockOutputAdapter.new
    @llm = SimpleMockLLM.new(responses: {
      "Hello" => { content: "Hi there!", usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
    })

    @harness = AgentHarness::Harness.new(
      agent_id: "test-agent-001",
      input: @input,
      output: @output,
      llm: @llm,
      config: { system_prompt: "You are a test assistant." }
    )
  end

  def test_initializes_with_dependencies
    assert_equal "test-agent-001", @harness.agent_id
    assert_equal @input, @harness.input
    assert_equal @output, @harness.output
    assert_equal @llm, @harness.llm
  end

  def test_not_running_initially
    refute @harness.running?
  end

  def test_processes_message_directly
    # Test process_message directly without starting harness
    message = {
      id: "msg-1",
      text: "Hello",
      chat_id: 123,
      timestamp: Time.now.iso8601
    }

    # Simulate what happens inside async loop
    @harness.send(:process_message, message)

    # Verify
    assert_equal 1, @llm.call_count
    assert_includes @output.messages, { text: "Hi there!", chat_id: 123 }
  end

  def test_handles_llm_errors
    @llm = SimpleMockLLM.new(raise_error: true)
    @harness = AgentHarness::Harness.new(
      agent_id: "test-agent-002",
      input: @input,
      output: @output,
      llm: @llm
    )

    message = {
      id: "msg-2",
      text: "Hello",
      chat_id: 123,
      timestamp: Time.now.iso8601
    }

    @harness.send(:process_message, message)

    # Should send "couldn't generate response" message when LLM errors
    msgs = @output.messages.select { |m| m[:text].include?("couldn't generate") }
    assert_equal 1, msgs.length
  end

  def test_builds_llm_messages
    incoming = { text: "Hello", chat_id: 123 }
    messages = @harness.send(:build_llm_messages, incoming)

    assert_equal 2, messages.length
    assert_equal "system", messages[0][:role]
    assert_equal "You are a test assistant.", messages[0][:content]
    assert_equal "user", messages[1][:role]
    assert_equal "Hello", messages[1][:content]
  end

  def test_system_prompt_uses_config
    assert_equal "You are a test assistant.", @harness.send(:system_prompt)
  end

  def test_default_system_prompt
    harness = AgentHarness::Harness.new(
      agent_id: "test-default",
      input: @input,
      output: @output,
      llm: @llm
    )
    assert_equal "You are a helpful assistant.", harness.send(:system_prompt)
  end

  def test_null_objects_available
    assert AgentHarness::NullMessageBus.new.respond_to?(:publish)
    assert AgentHarness::NullRegistry.new.respond_to?(:register)
    assert AgentHarness::NullLogger.new.respond_to?(:info)
    assert AgentHarness::NullMetrics.new.respond_to?(:increment)
  end
end
