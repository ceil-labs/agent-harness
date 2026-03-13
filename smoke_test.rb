#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke test for ObservabilityFactory and Metrics Server
# Verifies Falcon require bug is fixed

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "bundler/setup"
require "agent_harness"
require "async"

puts "=" * 60
puts "SMOKE TEST: Observability Factory & Metrics Server"
puts "=" * 60

# Test 1: Create metrics via factory
puts "\n[Test 1] Creating metrics via ObservabilityFactory..."
begin
  metrics = AgentHarness::ObservabilityFactory.create_metrics
  puts "  ✅ SUCCESS: Metrics created: #{metrics.class}"
  
  # Test recording a metric with both labels (verifies label fix)
  metrics.observe(:llm_request_duration_seconds, 0.5, labels: { agent_id: "test-agent", provider: "test-provider" })
  puts "  ✅ SUCCESS: Recorded metric with provider label"
rescue => e
  puts "  ❌ FAILED: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

# Test 2: Create metrics server (verifies Falcon require fix)
puts "\n[Test 2] Creating metrics server..."
begin
  server = AgentHarness::ObservabilityFactory.create_metrics_server(
    metrics: metrics,
    port: 9091  # Use different port to avoid conflicts
  )
  puts "  ✅ SUCCESS: Server created: #{server.class}"
rescue LoadError => e
  puts "  ❌ FAILED (LoadError - Falcon bug not fixed): #{e.message}"
  exit 1
rescue => e
  puts "  ❌ FAILED: #{e.class}: #{e.message}"
  exit 1
end

# Test 3: Start server briefly
puts "\n[Test 3] Starting metrics server..."
begin
  server_thread = Thread.new do
    server.start
  end
  
  # Give server time to start
  sleep 1
  
  # Check if thread is still running (server started)
  if server_thread.alive?
    puts "  ✅ SUCCESS: Server started and running"
    puts "  ✅ Falcon require bug FIXED - no LoadError!"
  else
    puts "  ❌ FAILED: Server died unexpectedly"
    exit 1
  end
  
  # Server runs in background thread - let it be
  puts "  ℹ️  Server continues running (stop method is a separate issue)"
rescue LoadError => e
  puts "  ❌ FAILED (LoadError - Falcon bug not fixed): #{e.message}"
  exit 1
rescue => e
  puts "  ❌ FAILED: #{e.class}: #{e.message}"
  exit 1
end

# Test 4: Create logger
puts "\n[Test 4] Creating logger..."
begin
  logger = AgentHarness::ObservabilityFactory.create_logger
  puts "  ✅ SUCCESS: Logger created: #{logger.class}"
rescue => e
  puts "  ❌ FAILED: #{e.class}: #{e.message}"
  exit 1
end

# Test 5: Create default stack
puts "\n[Test 5] Creating default observability stack..."
begin
  stack = AgentHarness::ObservabilityFactory.create_default(metrics_port: 9092)
  puts "  ✅ SUCCESS: Stack created with:"
  puts "     - logger: #{stack[:logger].class}"
  puts "     - metrics: #{stack[:metrics].class}"
  puts "     - metrics_server: #{stack[:metrics_server].class}"
rescue LoadError => e
  puts "  ❌ FAILED (LoadError - Falcon bug not fixed): #{e.message}"
  exit 1
rescue => e
  puts "  ❌ FAILED: #{e.class}: #{e.message}"
  exit 1
end

puts "\n" + "=" * 60
puts "ALL SMOKE TESTS PASSED ✅"
puts "=" * 60
puts "\nVerified fixes:"
puts "  1. ✅ Falcon require bug fixed (falcon/service/supervised removed)"
puts "  2. ✅ Metrics provider label added to llm_request_duration_seconds"
puts "  3. ✅ Metrics server starts without LoadError"
