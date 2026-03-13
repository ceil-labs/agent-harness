#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "agent_harness"
require "async"

puts "Creating observability stack..."
obs = AgentHarness::ObservabilityFactory.create_default(
  log_level: :info,
  metrics_port: 9090
)

puts "Recording test metrics..."
obs[:metrics].increment(:messages_total, labels: { agent_id: "test-harness" })
obs[:metrics].observe(:llm_request_duration_seconds, 0.85, labels: {
  agent_id: "test-harness",
  provider: "kimi-coding"
})
obs[:metrics].gauge(:up, 1, labels: { agent_id: "test-harness" })

puts "Starting metrics server on port 9090..."
puts "Test URLs:"
puts "  http://localhost:9090/health"
puts "  http://localhost:9090/metrics"
puts ""
puts "NOTE: Server binds to 127.0.0.1 by default for security"
puts "Use tailscale serve to expose externally if needed"
puts ""

# Write PID file
File.write("/tmp/metrics_server.pid", Process.pid.to_s)

# Keep the reactor running
Async do |task|
  server_task = task.async { obs[:metrics_server].start }
  
  # Keep main task alive
  loop do
    sleep 1
  end
end
