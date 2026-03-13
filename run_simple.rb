#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Phase 0 runner - no separate metrics thread

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"

puts "Agent Harness - Phase 0"
puts "-" * 40

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

trap("INT") { harness.stop; exit }

puts "Starting..."
harness.start
