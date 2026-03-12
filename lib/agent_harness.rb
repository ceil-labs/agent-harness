# frozen_string_literal: true

require_relative "agent_harness/version"

# Interfaces (contracts)
require_relative "interfaces/input_adapter"
require_relative "interfaces/output_adapter"
require_relative "interfaces/llm_provider"

# Core harness
require_relative "harness/harness"

# Observability
require_relative "observability/null_observability"

module AgentHarness
  # Error class for harness-specific errors
  class Error < StandardError; end

  # Error for configuration issues
  class ConfigurationError < Error; end

  # Error for adapter failures
  class AdapterError < Error; end

  # Error for LLM provider failures
  class LLMError < Error; end
end
