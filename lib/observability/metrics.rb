# frozen_string_literal: true

require "prometheus/client"
require "prometheus/client/registry"
require "prometheus/client/formats/text"

module AgentHarness
  # Prometheus metrics collector for agent harness
  # Uses the prometheus-client gem to expose metrics on /metrics endpoint
  class Metrics
    # Metric names and their types
    METRIC_DEFINITIONS = {
      # Counter: Total messages processed
      messages_total: {
        type: :counter,
        docstring: "Total number of messages processed",
        labels: [:agent_id]
      },
      # Histogram: LLM request latency
      llm_request_duration_seconds: {
        type: :histogram,
        docstring: "LLM request duration in seconds",
        labels: [:agent_id, :provider],
        buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
      },
      # Counter: Total errors
      errors_total: {
        type: :counter,
        docstring: "Total number of errors",
        labels: [:agent_id, :error_class]
      },
      # Gauge: Agent health status
      up: {
        type: :gauge,
        docstring: "Whether the agent is running (1) or not (0)",
        labels: [:agent_id]
      }
    }.freeze

    attr_reader :registry

    # @param registry [Prometheus::Client::Registry] Optional custom registry
    def initialize(registry: nil)
      @registry = registry || Prometheus::Client.registry
      @metrics = {}

      setup_metrics
    end

    # Increment a counter metric
    # @param metric [Symbol] Metric name
    # @param labels [Hash] Label values
    def increment(metric, labels: {})
      metric_obj = @metrics[metric]
      return unless metric_obj&.is_a?(Prometheus::Client::Counter)

      metric_obj.increment(labels: labels)
    end

    # Set a gauge metric value
    # @param metric [Symbol] Metric name
    # @param value [Numeric] Gauge value
    # @param labels [Hash] Label values
    def gauge(metric, value, labels: {})
      metric_obj = @metrics[metric]
      return unless metric_obj&.is_a?(Prometheus::Client::Gauge)

      metric_obj.set(value, labels: labels)
    end

    # Observe a value in a histogram
    # @param metric [Symbol] Metric name
    # @param value [Numeric] Value to observe
    # @param labels [Hash] Label values
    def observe(metric, value, labels: {})
      metric_obj = @metrics[metric]
      return unless metric_obj&.is_a?(Prometheus::Client::Histogram)

      metric_obj.observe(value, labels: labels)
    end

    # Alias for observe (matches NullMetrics interface)
    alias histogram observe

    # Get the Prometheus registry for exposition
    # @return [Prometheus::Client::Registry]
    def prometheus_registry
      @registry
    end

    # Return metrics in Prometheus exposition format
    # @return [String]
    def exposition_format
      Prometheus::Client::Formats::Text.marshal(@registry)
    end

    private

    def setup_metrics
      METRIC_DEFINITIONS.each do |name, config|
        @metrics[name] = register_metric(name, config)
      end
    end

    def register_metric(name, config)
      # Check if metric already exists in registry
      existing = @registry.get(name.to_sym)
      return existing if existing

      case config[:type]
      when :counter
        @registry.counter(name.to_sym, docstring: config[:docstring], labels: config[:labels])
      when :gauge
        @registry.gauge(name.to_sym, docstring: config[:docstring], labels: config[:labels])
      when :histogram
        buckets = config[:buckets] || Prometheus::Client::Histogram::DEFAULT_BUCKETS
        @registry.histogram(name.to_sym, docstring: config[:docstring], labels: config[:labels], buckets: buckets)
      end
    rescue Prometheus::Client::Registry::AlreadyRegisteredError
      # Metric was registered between check and registration
      @registry.get(name.to_sym)
    end
  end
end
