# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "agent_harness"

# Load contract tests
require_relative "interfaces/input_adapter_contract"
require_relative "interfaces/output_adapter_contract"
require_relative "interfaces/llm_provider_contract"

# Test timeout for async operations
TEST_TIMEOUT = 5

module Minitest
  class Test
    # Helper to run async code in tests
    def run_async(&block)
      Async { block.call }.wait
    end

    # Helper to wait for condition with timeout
    def wait_for(timeout: TEST_TIMEOUT, interval: 0.01)
      deadline = Time.now + timeout
      until yield
        raise Timeout::Error, "Condition not met within #{timeout}s" if Time.now > deadline
        sleep interval
      end
    end
  end
end
