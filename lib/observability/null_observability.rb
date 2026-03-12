# frozen_string_literal: true

module AgentHarness
  # Null logger for when no logger is provided
  class NullLogger
    def debug(event, context = {}); end
    def info(event, context = {}); end
    def warn(event, context = {}); end
    def error(event, context = {}); end
  end

  # Null metrics for when no metrics collector is provided
  class NullMetrics
    def increment(metric, labels: {}); end
    def gauge(metric, value, labels: {}); end
    def observe(metric, value, labels: {}); end
    def histogram(metric, value, labels: {}); end
  end
end
