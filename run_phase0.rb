#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 0 Full Harness Integration
# Telegram → Harness → Kimi LLM → Telegram Response

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"
require "async"

puts "=" * 60
puts "Agent Harness - Phase 0 Full Integration"
puts "=" * 60
puts ""

# Load secrets
begin
  secrets = AgentHarness::Secrets::FileProvider.new(
    master_key_path: "config/master.key",
    secrets_path: "config/secrets.yml.enc"
  )
  
  secrets.get("telegram.bot_token")
  secrets.get("kimi_coding.api_key")
  
  puts "✅ Secrets loaded"
rescue => e
  puts "❌ Failed to load secrets: #{e.message}"
  exit 1
end

# Create observability stack
obs = AgentHarness::ObservabilityFactory.create_default(
  log_level: :info,
  metrics_port: 9090
)

# Start metrics server in a thread (separate from async reactor)
Thread.new do
  begin
    Async { obs[:metrics_server].start }
  rescue => e
    puts "❌ Metrics server error: #{e.message}"
  end
end

sleep 2  # Let server start
puts "✅ Metrics server starting on port 9090"

# Create adapters
input_adapter = AgentHarness::Adapters::TelegramAdapter.new(
  secrets: secrets,
  logger: obs[:logger],
  allowlist: [8154042516]
)

output_adapter = AgentHarness::Adapters::TelegramAdapter.new(
  secrets: secrets,
  logger: obs[:logger]
)

llm = AgentHarness::Adapters::KimiCodingLLM.new(
  secrets: secrets,
  model: "k2p5"
)

puts "Checking components..."
puts "  Telegram: #{input_adapter.available? ? '✅' : '❌'}"
puts "  Kimi LLM: #{llm.available? ? '✅' : '❌'}"
puts ""

unless input_adapter.available? && llm.available?
  puts "❌ Components not available"
  exit 1
end

# Create harness
harness = AgentHarness::Harness.new(
  agent_id: "ceil-phase0",
  input: input_adapter,
  output: output_adapter,
  llm: llm,
  config: {
    system_prompt: "You are Ceil, a helpful AI assistant. Be concise and friendly."
  },
  logger: obs[:logger],
  metrics: obs[:metrics]
)

puts "🤖 Agent: Ceil (Phase 0)"
puts "💬 Platform: Telegram (@ceil_harness_bot)"
puts "🧠 LLM: Kimi for Coding (k2p5)"
puts "📊 Metrics: http://localhost:9090/metrics"
puts ""
puts "Send a message to @ceil_harness_bot on Telegram"
puts "Press Ctrl+C to stop"
puts "-" * 60

# Handle graceful shutdown
trap("INT") do
  puts "\n🛑 Shutting down..."
  harness.stop
  exit 0
end

# Run harness
begin
  harness.start
rescue => e
  puts "❌ Harness error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
