#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 0 Full Harness Integration
# Telegram → Harness → LLM → Telegram Response
#
# Configuration via ENV (non-secret) or secrets (API keys):
#   AGENT_ID        - Agent identifier (default: ceil-phase0)
#   MODEL           - LLM model (default depends on provider)
#   MODEL_PROVIDER  - LLM provider: opencode_go | kimi_coding (default: kimi_coding)
#   LOG_LEVEL       - Log level: debug/info/warn/error (default: info)
#   METRICS_PORT    - Prometheus metrics port (default: 9090)
#   ALLOWLIST       - Comma-separated Telegram user IDs (default: none)
#   SYSTEM_PROMPT   - System prompt for the agent (default: built-in)
#
# Secrets (use: bin/harness secrets_edit):
#   telegram.bot_token
#   kimi_coding.api_key      # For kimi_coding provider
#   opencode_go.api_key     # For opencode_go provider

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"
require "async"

# Configuration from ENV with defaults
AGENT_ID = ENV.fetch("AGENT_ID", "ceil-phase0")
MODEL_PROVIDER = ENV.fetch("MODEL_PROVIDER", "kimi_coding")
MODEL = ENV.fetch("MODEL", model_default(MODEL_PROVIDER))
LOG_LEVEL = ENV.fetch("LOG_LEVEL", "info").downcase.to_sym
METRICS_PORT = ENV.fetch("METRICS_PORT", "9090").to_i
HEALTH_CHECK_INTERVAL = ENV.fetch("HEALTH_CHECK_INTERVAL", "300").to_i
ALLOWLIST = ENV.fetch("ALLOWLIST", "")
  .split(",")
  .map(&:strip)
  .reject(&:empty?)
  .map(&:to_i)
SYSTEM_PROMPT = ENV.fetch("SYSTEM_PROMPT", "You are Ceil, a helpful AI assistant. Be concise and friendly.")

# Determine default model based on provider
def model_default(provider)
  case provider
  when "opencode_go"
    "kimi-k2.5"
  when "kimi_coding"
    "k2p5"
  else
    "k2p5"
  end
end

puts "=" * 60
puts "Agent Harness - Phase 0 Full Integration"
puts "=" * 60
puts ""
puts "Provider: #{MODEL_PROVIDER}"
puts "Model: #{MODEL}"
puts ""

# Load secrets
begin
  secrets = AgentHarness::Secrets::FileProvider.new(
    master_key_path: "config/master.key",
    secrets_path: "config/secrets.yml.enc"
  )

  secrets.get("telegram.bot_token")

  # Verify the correct API key exists for the selected provider
  case MODEL_PROVIDER
  when "opencode_go"
    secrets.get("opencode_go.api_key")
    puts "✅ Secrets loaded (opencode_go)"
  when "kimi_coding"
    secrets.get("kimi_coding.api_key")
    puts "✅ Secrets loaded (kimi_coding)"
  else
    raise "Unknown provider: #{MODEL_PROVIDER}"
  end
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

# Create LLM adapter based on MODEL_PROVIDER
llm = case MODEL_PROVIDER
      when "opencode_go"
        puts "Using OpenCode-go LLM adapter"
        AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: secrets, model: MODEL)
      when "kimi_coding"
        puts "Using Kimi Coding LLM adapter"
        AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets, model: MODEL)
      else
        puts "❌ Unknown provider: #{MODEL_PROVIDER}"
        exit 1
      end

puts "Checking components..."
puts "  Telegram: #{input_adapter.available? ? '✅' : '❌'}"
puts "  #{llm.name}: #{llm.available? ? '✅' : '❌'}"
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
    system_prompt: SYSTEM_PROMPT,
    health_check_interval: HEALTH_CHECK_INTERVAL
  },
  logger: obs[:logger],
  metrics: obs[:metrics]
)

puts "🤖 Agent: #{AGENT_ID}"
puts "💬 Platform: Telegram (@ceil_harness_bot)"
llm_name = MODEL_PROVIDER == "opencode_go" ? "OpenCode-go (#{MODEL})" : "Kimi for Coding (#{MODEL})"
puts "🧠 LLM: #{llm_name}"
puts "📊 Metrics: http://localhost:#{METRICS_PORT}/metrics"
puts "💚 Health Check: every #{HEALTH_CHECK_INTERVAL}s (lightweight mode)"
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
