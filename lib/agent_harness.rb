# frozen_string_literal: true

require "json"
require_relative "agent_harness/version"

module AgentHarness
  # Error class for harness-specific errors
  class Error < StandardError; end

  # Error for configuration issues
  class ConfigurationError < Error; end

  # Error for adapter failures
  class AdapterError < Error; end

  # Error for LLM provider failures
  class LLMError < Error; end

  # Factory methods for creating observability stacks
  class ObservabilityFactory
    # Create a default observability stack with real implementations
    #
    # @param log_level [Symbol] Log level (:debug, :info, :warn, :error, :fatal)
    # @param log_file [String, nil] Optional path to log file
    # @param metrics_port [Integer] Port for metrics server
    # @return [Hash] { logger: Logger, metrics: Metrics, metrics_server: MetricsServer }
    def self.create_default(log_level: :info, log_file: nil, metrics_port: 9090)
      logger = create_logger(level: log_level, file_path: log_file)
      metrics = create_metrics
      metrics_server = create_metrics_server(metrics: metrics, port: metrics_port)

      {
        logger: logger,
        metrics: metrics,
        metrics_server: metrics_server
      }
    end

    # Create a structured JSON logger
    #
    # @param level [Symbol] Log level
    # @param output [IO] Output stream (default: $stdout)
    # @param file_path [String, nil] Optional file path
    # @return [Logger]
    def self.create_logger(level: :info, output: $stdout, file_path: nil)
      require_relative "observability/logger"
      Logger.new(level: level, output: output, file_path: file_path)
    end

    # Create a Prometheus metrics collector
    #
    # @param registry [Prometheus::Client::Registry, nil] Custom registry
    # @return [Metrics]
    def self.create_metrics(registry: nil)
      require_relative "observability/metrics"
      Metrics.new(registry: registry)
    end

    # Create a metrics server
    #
    # @param metrics [Metrics] Metrics instance
    # @param port [Integer] Port to listen on
    # @param host [String] Host to bind to
    # @return [MetricsServer]
    def self.create_metrics_server(metrics:, port: 9090, host: "0.0.0.0")
      require_relative "observability/metrics_server"
      MetricsServer.new(metrics: metrics, port: port, host: host)
    end

    # Create null observability (for testing/no-op scenarios)
    #
    # @return [Hash] { logger: NullLogger, metrics: NullMetrics }
    def self.create_null
      require_relative "observability/null_observability"
      {
        logger: NullLogger.new,
        metrics: NullMetrics.new
      }
    end
  end
end

# Interfaces (contracts)
require_relative "interfaces/input_adapter"
require_relative "interfaces/output_adapter"
require_relative "interfaces/llm_provider"

# Core harness
require_relative "harness/harness"

# Observability (null objects available by default)
require_relative "observability/null_observability"

# Secrets
require_relative "secrets/file_provider"

# Adapters
require_relative "adapters/kimi_coding_llm"
require_relative "adapters/opencode_go_llm"
require_relative "adapters/telegram_adapter"
