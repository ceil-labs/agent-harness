# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/observability/metrics"

class MetricsTest < Minitest::Test
  def setup
    # Use a fresh registry for each test to avoid conflicts
    @registry = Prometheus::Client::Registry.new
    @metrics = AgentHarness::Metrics.new(registry: @registry)
  end

  def test_initializes_with_default_registry
    metrics = AgentHarness::Metrics.new
    assert metrics.prometheus_registry
    assert_instance_of Prometheus::Client::Registry, metrics.prometheus_registry
  end

  def test_initializes_with_custom_registry
    custom_registry = Prometheus::Client::Registry.new
    metrics = AgentHarness::Metrics.new(registry: custom_registry)
    assert_equal custom_registry, metrics.prometheus_registry
  end

  def test_registers_messages_total_counter
    counter = @registry.get(:messages_total)
    assert_instance_of Prometheus::Client::Counter, counter
    assert_equal "Total number of messages processed", counter.docstring
    assert_equal [:agent_id], counter.labels
  end

  def test_registers_llm_request_duration_histogram
    histogram = @registry.get(:llm_request_duration_seconds)
    assert_instance_of Prometheus::Client::Histogram, histogram
    assert_equal "LLM request duration in seconds", histogram.docstring
    assert_equal [:agent_id, :provider], histogram.labels
  end

  def test_registers_errors_total_counter
    counter = @registry.get(:errors_total)
    assert_instance_of Prometheus::Client::Counter, counter
    assert_equal "Total number of errors", counter.docstring
    assert_equal [:agent_id, :error_class], counter.labels
  end

  def test_registers_up_gauge
    gauge = @registry.get(:up)
    assert_instance_of Prometheus::Client::Gauge, gauge
    assert_equal "Whether the agent is running (1) or not (0)", gauge.docstring
    assert_equal [:agent_id], gauge.labels
  end

  def test_increments_messages_total
    @metrics.increment(:messages_total, labels: { agent_id: "test-agent" })

    # Verify through exposition format
    exposition = @metrics.exposition_format
    assert_includes exposition, "messages_total"
    assert_includes exposition, 'agent_id="test-agent"'
    assert_includes exposition, "1.0" # Counter value
  end

  def test_increments_messages_total_multiple_times
    @metrics.increment(:messages_total, labels: { agent_id: "test-agent" })
    @metrics.increment(:messages_total, labels: { agent_id: "test-agent" })
    @metrics.increment(:messages_total, labels: { agent_id: "test-agent" })

    exposition = @metrics.exposition_format
    assert_includes exposition, "3.0"
  end

  def test_increments_errors_total_with_labels
    @metrics.increment(:errors_total, labels: {
      agent_id: "test-agent",
      error_class: "RuntimeError"
    })

    exposition = @metrics.exposition_format
    assert_includes exposition, "errors_total"
    assert_includes exposition, 'error_class="RuntimeError"'
  end

  def test_sets_up_gauge
    @metrics.gauge(:up, 1, labels: { agent_id: "test-agent" })

    exposition = @metrics.exposition_format
    assert_includes exposition, "up"
    assert_includes exposition, 'agent_id="test-agent"'
    assert_includes exposition, "1.0"
  end

  def test_sets_up_gauge_to_zero
    @metrics.gauge(:up, 0, labels: { agent_id: "test-agent" })

    exposition = @metrics.exposition_format
    assert_includes exposition, "0.0"
  end

  def test_observes_llm_request_duration
    @metrics.observe(:llm_request_duration_seconds, 0.5, labels: {
      agent_id: "test-agent",
      provider: "openai"
    })

    exposition = @metrics.exposition_format
    assert_includes exposition, "llm_request_duration_seconds"
    assert_includes exposition, 'provider="openai"'
  end

  def test_histogram_alias
    # histogram is an alias for observe
    @metrics.histogram(:llm_request_duration_seconds, 1.0, labels: {
      agent_id: "test-agent",
      provider: "kimi"
    })

    exposition = @metrics.exposition_format
    assert_includes exposition, 'provider="kimi"'
  end

  def test_handles_symbol_labels
    @metrics.increment(:messages_total, labels: { agent_id: "test-agent" })

    # Should work with symbol keys
    exposition = @metrics.exposition_format
    assert_includes exposition, 'agent_id="test-agent"'
  end

  def test_handles_missing_metric_gracefully
    # Should not raise when incrementing non-existent metric
    @metrics.increment(:non_existent_metric, labels: { agent_id: "test" })

    # Should not raise when setting non-existent gauge
    @metrics.gauge(:non_existent_gauge, 1, labels: { agent_id: "test" })

    # Should not raise when observing non-existent histogram
    @metrics.observe(:non_existent_histogram, 1.0, labels: { agent_id: "test" })
  end

  def test_handles_wrong_metric_type_gracefully
    # Try to use gauge as counter (should be no-op)
    @metrics.increment(:up, labels: { agent_id: "test" })

    # Try to use counter as gauge (should be no-op)
    @metrics.gauge(:messages_total, 1, labels: { agent_id: "test" })

    # Should not raise
    pass
  end

  def test_exposition_format_returns_prometheus_text
    @metrics.increment(:messages_total, labels: { agent_id: "agent-1" })
    @metrics.gauge(:up, 1, labels: { agent_id: "agent-1" })

    exposition = @metrics.exposition_format

    # Should be Prometheus text format
    assert_includes exposition, "# HELP messages_total"
    assert_includes exposition, "# TYPE messages_total counter"
    assert_includes exposition, "# HELP up"
    assert_includes exposition, "# TYPE up gauge"
  end

  def test_metrics_are_isolated_by_labels
    @metrics.increment(:messages_total, labels: { agent_id: "agent-1" })
    @metrics.increment(:messages_total, labels: { agent_id: "agent-2" })
    @metrics.increment(:messages_total, labels: { agent_id: "agent-1" })

    exposition = @metrics.exposition_format

    # Should have separate series for each agent_id
    assert_includes exposition, 'agent_id="agent-1"'
    assert_includes exposition, 'agent_id="agent-2"'
  end

  def test_matches_null_metrics_interface
    null_metrics = AgentHarness::NullMetrics.new
    real_metrics = AgentHarness::Metrics.new(registry: Prometheus::Client::Registry.new)

    # Ensure all methods exist on both
    assert null_metrics.respond_to?(:increment)
    assert null_metrics.respond_to?(:gauge)
    assert null_metrics.respond_to?(:observe)
    assert null_metrics.respond_to?(:histogram)

    assert real_metrics.respond_to?(:increment)
    assert real_metrics.respond_to?(:gauge)
    assert real_metrics.respond_to?(:observe)
    assert real_metrics.respond_to?(:histogram)

    # Ensure methods accept same signatures
    null_metrics.increment(:test, labels: { agent_id: "test" })
    real_metrics.increment(:messages_total, labels: { agent_id: "test" })

    null_metrics.gauge(:test, 1, labels: { agent_id: "test" })
    real_metrics.gauge(:up, 1, labels: { agent_id: "test" })

    null_metrics.observe(:test, 1.0, labels: { agent_id: "test" })
    real_metrics.observe(:llm_request_duration_seconds, 1.0, labels: { agent_id: "test", provider: "test" })
  end
end
