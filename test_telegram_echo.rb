#!/usr/bin/env ruby
# frozen_string_literal: true

# Telegram Echo Test
# Simple integration test for the Telegram adapter
# Receives messages and echoes them back

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"

puts "=" * 50
puts "Telegram Adapter Integration Test"
puts "=" * 50
puts ""

# Load secrets
begin
  secrets = AgentHarness::Secrets::FileProvider.new(
    master_key_path: "config/master.key",
    secrets_path: "config/secrets.yml.enc"
  )
  
  # Verify token exists
  token = secrets.get("telegram.bot_token")
  puts "✅ Bot token loaded"
rescue => e
  puts "❌ Failed to load secrets: #{e.message}"
  puts "   Run: bin/harness secrets_edit"
  puts "   Add: telegram: { bot_token: \"YOUR_TOKEN\" }"
  exit 1
end

# Create adapter with logger and allowlist
logger = AgentHarness::ObservabilityFactory.create_logger(level: :info)
adapter = AgentHarness::Adapters::TelegramAdapter.new(
  secrets: secrets,
  logger: logger,
  allowlist: [8154042516]  # Only respond to Victor
)

# Check if bot is available
puts "Checking bot availability..."
if adapter.available?
  puts "✅ Bot is online"
else
  puts "❌ Bot is not available (check token)"
  exit 1
end

puts ""
puts "🤖 Bot: @ceil_harness_bot"
puts "📱 Send a message to the bot on Telegram"
puts "🔄 It will echo your message back"
puts ""
puts "Press Ctrl+C to stop"
puts "-" * 50

# Handle graceful shutdown
trap("INT") do
  puts "\n🛑 Shutting down..."
  adapter.stop
  exit 0
end

# Start listening and echoing
begin
  adapter.listen do |message|
    puts "\n📨 Received message:"
    puts "   From: #{message[:sender_id]}"
    puts "   Chat: #{message[:chat_id]}"
    puts "   Text: #{message[:text]}"
    
    # Echo back
    reply_text = "Echo: #{message[:text]}"
    result = adapter.send(reply_text, context: { 
      chat_id: message[:chat_id],
      reply_to_message_id: message[:id]
    })
    
    if result[:success]
      puts "✅ Replied: #{reply_text}"
    else
      puts "❌ Failed to reply: #{result[:error]}"
    end
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end
