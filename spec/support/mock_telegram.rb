# frozen_string_literal: true

require "json"
require_relative "../fixtures/telegram_messages"

module AgentHarness
  module Test
    # Mock Telegram client for integration testing
    # Stubs HTTP requests to Telegram Bot API without requiring real API calls
    class MockTelegramClient
      attr_reader :requests, :responses, :bot_token

      def initialize(bot_token: "test_token")
        @bot_token = bot_token
        @requests = []
        @responses = {}
        @message_id_counter = 1000
      end

      # Stub a response for a specific API method
      def stub_method(method, response)
        @responses[method.to_s] = response
      end

      # Stub send_message to return a successful response
      def stub_send_message(options = {})
        stub_method("sendMessage", {
          "ok" => true,
          "result" => TelegramFixtures.send_message_response(options)
        })
      end

      # Stub getMe to return bot info
      def stub_get_me(options = {})
        stub_method("getMe", TelegramFixtures.bot_info(options))
      end

      # Stub getMe to simulate a failure
      def stub_get_me_failure(error_message = "Unauthorized")
        stub_method("getMe", {
          "ok" => false,
          "error_code" => 401,
          "description" => error_message
        })
      end

      # Stub send_message to simulate a failure
      def stub_send_message_failure(error_message = "Bad Request: message text is empty")
        stub_method("sendMessage", {
          "ok" => false,
          "error_code" => 400,
          "description" => error_message
        })
      end

      # Simulate receiving a message from Telegram
      # Returns an update that would come from getUpdates
      def simulate_message(message_fixture = nil)
        message_fixture ||= TelegramFixtures.text_message
        TelegramFixtures.webhook_update(message: message_fixture)
      end

      # Build the full API URL for a method
      def api_url(method)
        "https://api.telegram.org/bot#{@bot_token}/#{method}"
      end

      # Record a request that was made
      def record_request(method, params)
        @requests << { method: method, params: params, timestamp: Time.now }
      end

      # Get the last request made
      def last_request
        @requests.last
      end

      # Check if a request was made to a specific method
      def requested?(method)
        @requests.any? { |r| r[:method] == method.to_s }
      end

      # Clear all recorded requests
      def clear_requests
        @requests.clear
      end

      # Generate a new message ID
      def next_message_id
        @message_id_counter += 1
      end
    end

    # Mock Telegram adapter that uses the mock client
    # This wraps the real adapter but intercepts HTTP calls
    class MockTelegramAdapter
      include AgentHarness::InputAdapter
      include AgentHarness::OutputAdapter

      attr_reader :client, :messages, :sent_messages

      def initialize(options = {})
        @client = MockTelegramClient.new(
          bot_token: options[:bot_token] || "test_token"
        )
        @messages = []
        @sent_messages = []
        @listeners = []
        @listening = false
        @allowlist = options[:allowlist]
        @logger = options[:logger]
      end

      # Simulate receiving a message - injects into listeners
      def inject_message(message_data)
        standardized = standardize_message(message_data)
        
        # Check allowlist
        if @allowlist && !@allowlist.include?(standardized[:sender_id])
          @logger&.warn("mock_telegram.unauthorized", sender_id: standardized[:sender_id])
          return false
        end

        @messages << standardized
        @listeners.each { |l| l.call(standardized) }
        true
      end

      # Start listening (simulated - doesn't actually poll)
      def listen(&block)
        @listeners << block
        @listening = true
        @logger&.info("mock_telegram.listen_started")
      end

      # Stop listening
      def stop
        @listening = false
        @listeners.clear
        @logger&.info("mock_telegram.stopped")
      end

      def stopped?
        !@listening
      end

      # Send a message (mock implementation)
      def send(message, context: {})
        chat_id = context[:chat_id]
        unless chat_id
          return { success: false, message_id: nil, error: "Missing chat_id" }
        end

        # Record the sent message
        sent = {
          text: message,
          chat_id: chat_id,
          reply_to_message_id: context[:reply_to_message_id],
          message_id: @client.next_message_id,
          timestamp: Time.now
        }
        @sent_messages << sent

        @logger&.info("mock_telegram.message_sent", {
          chat_id: chat_id,
          message_id: sent[:message_id],
          text_preview: message&.[](0..50)
        })

        # Return mock API response
        { success: true, message_id: sent[:message_id].to_s }
      end

      def supports_streaming?
        true
      end

      def stream(chunk, context:, finished: false)
        # In a mock, we just accumulate the chunks
        context[:accumulated] ||= ""
        context[:accumulated] += chunk

        if context[:message_id].nil?
          # First chunk - "send" initial message
          result = send(chunk, context: context)
          context[:message_id] = result[:message_id]
        else
          # Subsequent chunks - "edit" message (just update our record)
          sent = @sent_messages.find { |m| m[:message_id].to_s == context[:message_id].to_s }
          sent[:text] = context[:accumulated] if sent
        end
      end

      # Always available in test mode
      def available?
        true
      end

      private

      def standardize_message(telegram_message)
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
  end
end
