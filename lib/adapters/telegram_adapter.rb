# frozen_string_literal: true

require "async"
require "telegram/bot"

module AgentHarness
  module Adapters
    # Telegram adapter for agent-harness
    # Implements both InputAdapter and OutputAdapter
    # Uses telegram-bot-ruby gem with long-polling
    #
    # Example usage:
    #   secrets = AgentHarness::Secrets::FileProvider.new(...)
    #   adapter = AgentHarness::Adapters::TelegramAdapter.new(secrets: secrets)
    #
    #   # Input: Listen for messages
    #   adapter.listen do |message|
    #     puts "Received: #{message[:text]}"
    #   end
    #
    #   # Output: Send response
    #   adapter.send("Hello!", context: { chat_id: 123456 })
    #
    class TelegramAdapter
      include AgentHarness::InputAdapter
      include AgentHarness::OutputAdapter

      # @param secrets [AgentHarness::Secrets::FileProvider] Secrets provider
      # @param logger [Logger] Optional logger instance
      def initialize(secrets:, logger: nil)
        @secrets = secrets
        @logger = logger
        @bot = nil
        @listening = false
        @stop_signal = Async::Condition.new
      end

      # Start listening for incoming Telegram messages
      # Uses long-polling via telegram-bot-ruby
      #
      # @yieldparam message [Hash] Standardized message format
      # @return [void]
      def listen(&block)
        return if @listening

        @listening = true
        @logger&.info("telegram_adapter.listen_start", {}) if @logger

        Async do
          begin
            Telegram::Bot::Client.run(bot_token) do |bot|
              @bot = bot

              bot.listen do |telegram_message|
                break unless @listening

                # Skip non-message updates (edits, callbacks, etc.)
                next unless telegram_message.is_a?(Telegram::Bot::Types::Message)
                next unless telegram_message.text

                standardized = standardize_message(telegram_message)
                @logger&.info("telegram_adapter.message_received", {
                  message_id: standardized[:id],
                  chat_id: standardized[:chat_id],
                  text_preview: standardized[:text][0..50]
                }) if @logger

                yield(standardized)
              end
            end
          rescue => e
            @logger&.error("telegram_adapter.listen_error", {
              error: e.message,
              error_class: e.class.name
            }) if @logger
            raise
          ensure
            @listening = false
          end
        end
      end

      # Stop listening for messages
      # @return [void]
      def stop
        @listening = false
        @bot&.stop
        @logger&.info("telegram_adapter.stopped", {}) if @logger
      end

      # Check if adapter is stopped
      # @return [Boolean]
      def stopped?
        !@listening
      end

      # Send a message to Telegram
      #
      # @param message [String] Message content
      # @param context [Hash] Context with :chat_id, optional :reply_to_message_id
      # @return [Hash] Result with :success, :message_id
      def send(message, context: {})
        chat_id = context[:chat_id]
        unless chat_id
          return { success: false, message_id: nil, error: "Missing chat_id" }
        end

        Async do
          bot = Telegram::Bot::Client.new(bot_token)

          options = { chat_id: chat_id, text: message }
          options[:reply_to_message_id] = context[:reply_to_message_id] if context[:reply_to_message_id]

          result = bot.api.send_message(options)

          # result is a Telegram::Bot::Types::Message object
          message_id = result.respond_to?(:message_id) ? result.message_id : nil

          @logger&.info("telegram_adapter.message_sent", {
            chat_id: chat_id,
            message_id: message_id
          }) if @logger

          {
            success: true,
            message_id: message_id&.to_s
          }
        rescue => e
          @logger&.error("telegram_adapter.send_error", {
            error: e.message,
            chat_id: chat_id
          }) if @logger

          { success: false, message_id: nil, error: e.message }
        end.wait
      end

      # Telegram supports streaming via message editing
      # @return [Boolean]
      def supports_streaming?
        true
      end

      # Stream a chunk to Telegram by editing the message
      # On first call, sends initial message; subsequent calls edit it
      #
      # @param chunk [String] Partial message content
      # @param context [Hash] Context with :chat_id, :message_id (set on first call)
      # @param finished [Boolean] true if this is the final chunk
      # @return [void]
      def stream(chunk, context:, finished: false)
        Async do
          bot = Telegram::Bot::Client.new(bot_token)
          chat_id = context[:chat_id]

          if context[:message_id].nil?
            # First chunk: send new message
            result = bot.api.send_message(chat_id: chat_id, text: chunk)
            context[:message_id] = result.respond_to?(:message_id) ? result.message_id : nil
          else
            # Subsequent chunks: edit message
            bot.api.edit_message_text(
              chat_id: chat_id,
              message_id: context[:message_id],
              text: chunk
            )
          end
        rescue => e
          @logger&.error("telegram_adapter.stream_error", {
            error: e.message,
            chat_id: chat_id
          }) if @logger
        end.wait
      end

      # Check if Telegram bot is configured and reachable
      # @return [Boolean]
      def available?
        return false unless bot_token_configured?

        Async do
          bot = Telegram::Bot::Client.new(bot_token)
          bot.api.get_me
          true
        rescue
          false
        end.wait
      end

      private

      def bot_token
        @secrets.get("telegram.bot_token")
      end

      def bot_token_configured?
        token = @secrets.get("telegram.bot_token")
        token && !token.empty?
      rescue
        false
      end

      # Convert Telegram message to standardized format
      def standardize_message(telegram_message)
        {
          id: telegram_message.message_id.to_s,
          text: telegram_message.text,
          chat_id: telegram_message.chat.id,
          sender_id: telegram_message.from&.id,
          timestamp: Time.at(telegram_message.date).utc.iso8601,
          metadata: {
            telegram_message: telegram_message.to_h,
            chat_type: telegram_message.chat.type
          }
        }
      end
    end
  end
end
