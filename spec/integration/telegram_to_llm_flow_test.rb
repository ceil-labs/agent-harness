# frozen_string_literal: true

require_relative "test_helper"
require_relative "../../lib/harness/harness"

# Integration test: Full Telegram → Harness → LLM → Response flow
# Tests the complete message processing pipeline
class TelegramToLLMFlowTest < AgentHarness::Test::IntegrationTest
  def setup
    super
    @secrets = mock_secrets
    @telegram_adapter = AgentHarness::Test::MockTelegramAdapter.new(
      bot_token: "test_token",
      allowlist: [81_540_425_16]
    )
  end

  # Happy path: Message flows through the entire system
  def test_full_flow_message_received_and_responded
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "Hello, bot!" => {
          content: "Hello! How can I help you today?",
          usage: { prompt_tokens: 10, completion_tokens: 8, total_tokens: 18 },
          finish_reason: "stop"
        }
      }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-flow",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm,
      config: { system_prompt: "You are a helpful test assistant." }
    )

    message = TelegramFixtures.text_message(text: "Hello, bot!")
    harness.send(:process_message, standardize_fixture(message))
    
    # Verify response was sent
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal "Hello! How can I help you today?", @telegram_adapter.sent_messages.first[:text]
    assert_equal message["chat"]["id"], @telegram_adapter.sent_messages.first[:chat_id]
  end

  # Test message transformation at each boundary
  def test_message_transformation_standardized_format
    raw_message = TelegramFixtures.text_message(
      text: "Test transformation",
      message_id: 999,
      chat_id: 12345,
      sender_id: 67890
    )
    
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: { "Test transformation" => { content: "OK", usage: default_usage, finish_reason: "stop" } }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-transform",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )
    
    harness.send(:process_message, standardize_fixture(raw_message))
    
    # Verify LLM received properly formatted messages
    assert_equal 1, llm.call_count
    assert llm.last_messages
    
    # Should have system + user messages
    assert_equal 2, llm.last_messages.length
    assert_equal "system", llm.last_messages[0][:role]
    assert_equal "user", llm.last_messages[1][:role]
    assert_equal "Test transformation", llm.last_messages[1][:content]
  end

  # Test multiple sequential messages
  def test_multiple_messages_processed_sequentially
    messages = TelegramFixtures.message_sequence
    
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "First message" => { content: "Response 1", usage: default_usage, finish_reason: "stop" },
        "Second message" => { content: "Response 2", usage: default_usage, finish_reason: "stop" },
        "Third message" => { content: "Response 3", usage: default_usage, finish_reason: "stop" }
      }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-multi",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )
    
    messages.each do |msg|
      harness.send(:process_message, standardize_fixture(msg))
    end
    
    assert_equal 3, llm.call_count
    assert_equal 3, @telegram_adapter.sent_messages.length
    
    responses = @telegram_adapter.sent_messages.map { |m| m[:text] }
    assert_includes responses, "Response 1"
    assert_includes responses, "Response 2"
    assert_includes responses, "Response 3"
  end

  # Test group chat message handling
  def test_group_chat_message_flow
    group_message = TelegramFixtures.group_message(
      text: "Hello from group!",
      chat_id: -100_123_456_789
    )
    
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "Hello from group!" => {
          content: "Hello group chat!",
          usage: default_usage,
          finish_reason: "stop"
        }
      }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-group",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )
    
    harness.send(:process_message, standardize_fixture(group_message))
    
    assert_equal 1, @telegram_adapter.sent_messages.length
    assert_equal(-100_123_456_789, @telegram_adapter.sent_messages.first[:chat_id])
  end

  # Test special characters in messages
  def test_special_characters_handled_correctly
    special_message = TelegramFixtures.special_chars_message(
      text: "Hello with emojis 🎉 and unicode 中文"
    )
    
    llm = AgentHarness::Test::MockLLMProvider.new(
      provider_type: :kimi_coding,
      responses: {
        "Hello with emojis" => {
          content: "Received your unicode: 🎉 中文",
          usage: default_usage,
          finish_reason: "stop"
        }
      }
    )
    
    harness = AgentHarness::Harness.new(
      agent_id: "test-unicode",
      input: @telegram_adapter,
      output: @telegram_adapter,
      llm: llm
    )
    
    harness.send(:process_message, standardize_fixture(special_message))
    
    assert @telegram_adapter.sent_messages.first[:text].include?("🎉")
    assert @telegram_adapter.sent_messages.first[:text].include?("中文")
  end

  private

  def default_usage
    { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
  end
  
  # Convert Telegram fixture to standardized message format
  def standardize_fixture(telegram_message)
    {
      id: telegram_message["message_id"].to_s,
      text: telegram_message["text"],
      chat_id: telegram_message["chat"]["id"],
      sender_id: telegram_message["from"]["id"],
      timestamp: Time.at(telegram_message["date"]).utc.iso8601,
      metadata: {
        telegram_message: telegram_message,
        chat_type: telegram_message["chat"]["type"]
      }
    }
  end
end
