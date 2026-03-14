# frozen_string_literal: true

# Sample Telegram message payloads for integration testing
# These fixtures represent the raw Telegram Bot API message format

module TelegramFixtures
  # Standard text message from a user
  def self.text_message(options = {})
    {
      "message_id" => options[:message_id] || 123_456,
      "from" => {
        "id" => options[:sender_id] || 81_540_425_16,
        "is_bot" => false,
        "first_name" => options[:first_name] || "Victor",
        "username" => options[:username] || "test_user"
      },
      "chat" => {
        "id" => options[:chat_id] || 81_540_425_16,
        "first_name" => options[:first_name] || "Victor",
        "username" => options[:username] || "test_user",
        "type" => "private"
      },
      "date" => options[:date] || Time.now.to_i,
      "text" => options[:text] || "Hello, this is a test message"
    }
  end

  # Message with a longer text
  def self.long_text_message(options = {})
    text_message(
      options.merge(
        text: options[:text] || "This is a longer test message with multiple sentences. " \
                                "It should still be processed correctly by the harness. " \
                                "Testing the full flow from Telegram to LLM and back."
      )
    )
  end

  # Message from a group chat
  def self.group_message(options = {})
    {
      "message_id" => options[:message_id] || 789_012,
      "from" => {
        "id" => options[:sender_id] || 81_540_425_16,
        "is_bot" => false,
        "first_name" => options[:first_name] || "Victor",
        "username" => options[:username] || "test_user"
      },
      "chat" => {
        "id" => options[:chat_id] || -100_123_456_789,
        "title" => options[:group_name] || "Test Group",
        "type" => "supergroup"
      },
      "date" => options[:date] || Time.now.to_i,
      "text" => options[:text] || "Hello from the group chat!"
    }
  end

  # Message with special characters
  def self.special_chars_message(options = {})
    text_message(
      options.merge(
        text: options[:text] || "Hello! Special chars: ñ, é, ü, 中文, 🎉, <b>HTML</b>, &amp; more"
      )
    )
  end

  # Simulated webhook update payload (what Telegram sends to webhook)
  def self.webhook_update(options = {})
    {
      "update_id" => options[:update_id] || 123_456_789,
      "message" => options[:message] || text_message(options)
    }
  end

  # Expected response from Telegram sendMessage API
  def self.send_message_response(options = {})
    {
      "message_id" => options[:message_id] || 654_321,
      "from" => {
        "id" => 123_456_789,
        "is_bot" => true,
        "first_name" => "TestBot",
        "username" => "test_bot"
      },
      "chat" => {
        "id" => options[:chat_id] || 81_540_425_16,
        "first_name" => options[:first_name] || "Victor",
        "username" => options[:username] || "test_user",
        "type" => "private"
      },
      "date" => Time.now.to_i,
      "text" => options[:text] || "This is the bot response",
      "reply_to_message" => options[:reply_to_message]
    }
  end

  # Multiple messages for batch testing
  def self.message_sequence
    [
      text_message(message_id: 1, text: "First message"),
      text_message(message_id: 2, text: "Second message"),
      text_message(message_id: 3, text: "Third message")
    ]
  end

  # Bot info response from getMe API
  def self.bot_info(options = {})
    {
      "ok" => true,
      "result" => {
        "id" => options[:bot_id] || 123_456_789,
        "is_bot" => true,
        "first_name" => options[:first_name] || "TestBot",
        "username" => options[:username] || "test_bot",
        "can_join_groups" => true,
        "can_read_all_group_messages" => false,
        "supports_inline_queries" => false
      }
    }
  end
end
