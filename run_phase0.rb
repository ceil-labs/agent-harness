#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 0 Full Harness Integration
# Telegram → Harness → Kimi LLM → Telegram Response
#
# Configuration via ENV (non-secret) or secrets (API keys):
#   AGENT_ID      - Agent identifier (default: ceil-phase0)
#   MODEL         - LLM model (default: k2p5)
#   LOG_LEVEL     - Log level: debug/info/warn/error (default: info)
#   METRICS_PORT  - Prometheus metrics port (default: 9090)
#   ALLOWLIST     - Comma-separated Telegram user IDs (default: none)
#   SYSTEM_PROMPT - System prompt for the agent (default: built-in)
#
# Secrets (use: bin/harness secrets_edit):
#   telegram.bot_token
#   kimi_coding.api_key

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"
require "async"

# Configuration from ENV with defaults
AGENT_ID = ENV.fetch("AGENT_ID", "ceil-phase0")
MODEL = ENV.fetch("MODEL", "k2p5")
LOG_LEVEL = ENV.fetch("LOG_LEVEL", "info").downcase.to_sym
METRICS_PORT = ENV.fetch("METRICS_PORT", "9090").to_i
ALLOWLIST = ENV.fetch("ALLOWLIST", "")
  .split(",")
  .map(&:strip)
  .reject(&:empty?)
  .map(&:to_i)
SYSTEM_PROMPT = ENV.fetch("SYSTEM_PROMPT", "You are Ceil, a helpful AI assistant. Be concise and friendly.")
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
  log_level: LOG_LEVEL,
  metrics_port: METRICS_PORT
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
puts "✅ Metrics server starting on port #{METRICS_PORT}"

# Create adapters
input_adapter = AgentHarness::Adapters::TelegramAdapter.new(
  secrets: secrets,
  logger: obs[:logger],
  allowlist: ALLOWLIST.empty? ? nil : ALLOWLIST
)

output_adapter = AgentHarness::Adapters::TelegramAdapter.new(
  secrets: secrets,
  logger: obs[:logger]
)

llm = AgentHarness::Adapters::KimiCodingLLM.new(
  secrets: secrets,
  model: MODEL
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
  agent_id: AGENT_ID,
  input: input_adapter,
  output: output_adapter,
  llm: llm,
  config: {
    system_prompt: SYSTEM_PROMPT
  },
  logger: obs[:logger],
  metrics: obs[:metrics]
)

puts "🤖 Agent: #{AGENT_ID}"
puts "💬 Platform: Telegram (@ceil_harness_bot)"
puts "🧠 LLM: Kimi for Coding (#{MODEL})"
puts "📊 Metrics: http://localhost:#{METRICS_PORT}/metrics"
puts "🔐 Allowlist: #{ALLOWLIST.empty? ? 'all users' : ALLOWLIST.join(', ')}"
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
