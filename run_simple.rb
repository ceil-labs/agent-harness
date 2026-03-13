#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Phase 0 runner - Docker-friendly with proper signal handling

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"
require "async"

puts "Agent Harness - Phase 0"
puts "PID: #{Process.pid}"
puts "-" * 40

# Ignore SIGHUP (sent when terminal detaches)
Signal.trap("HUP", "IGNORE")

# Handle graceful shutdown
shutdown_requested = false

%w[INT TERM].each do |signal|
  Signal.trap(signal) do
    puts "\n🛑 Shutdown requested (#{signal})..."
    shutdown_requested = true
  end
end

begin
  secrets = AgentHarness::Secrets::FileProvider.new(
    master_key_path: "config/master.key",
    secrets_path: "config/secrets.yml.enc"
  )

  logger = AgentHarness::ObservabilityFactory.create_logger(level: :info)
  metrics = AgentHarness::ObservabilityFactory.create_metrics

  input = AgentHarness::Adapters::TelegramAdapter.new(
    secrets: secrets,
    logger: logger,
    allowlist: [8154042516]
  )

  output = AgentHarness::Adapters::TelegramAdapter.new(
    secrets: secrets,
    logger: logger
  )

  llm = AgentHarness::Adapters::KimiCodingLLM.new(
    secrets: secrets,
    model: "k2p5"
  )

  harness = AgentHarness::Harness.new(
    agent_id: "ceil-phase0",
    input: input,
    output: output,
    llm: llm,
    config: { system_prompt: "You are Ceil, a helpful AI assistant." },
    logger: logger,
    metrics: metrics
  )

  puts "✅ Harness initialized"
  puts "🤖 Agent: Ceil (Phase 0)"
  puts "💬 Platform: Telegram"
  puts "🧠 LLM: Kimi for Coding (k2p5)"
  puts ""
  puts "Starting harness..."
  puts "-" * 40

  # Run harness in async context with shutdown monitoring
  Async do
    harness_task = Async { harness.start }

    # Monitor for shutdown
    loop do
      if shutdown_requested
        puts "Stopping harness..."
        harness.stop
        break
      end
      sleep 1
    end

    harness_task.wait
  end

rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts "Harness stopped."

