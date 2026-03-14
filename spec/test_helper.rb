# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "async"
require "agent_harness"

# Load contract tests
require_relative "interfaces/input_adapter_contract"
require_relative "interfaces/output_adapter_contract"
require_relative "interfaces/llm_provider_contract"

# Load test support
require_relative "support/mock_adapters"

# WebMock and VCR for HTTP stubbing in integration tests
require "webmock/minitest"
require "vcr"

# Configure VCR for recording/replaying HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = false
  # Note: configure_rspec_metadata! only works with RSpec
  # For Minitest, we manually manage cassettes
  
  # Filter sensitive data
  config.filter_sensitive_data("<TELEGRAM_BOT_TOKEN>") do
    ENV["TELEGRAM_BOT_TOKEN"] || "test_token"
  end
  config.filter_sensitive_data("<KIMI_API_KEY>") do
    ENV["KIMI_API_KEY"] || "mock_kimi_key"
  end
  config.filter_sensitive_data("<OPENCODE_GO_API_KEY>") do
    ENV["OPENCODE_GO_API_KEY"] || "mock_opencode_key"
  end
end

# Test timeout for async operations
TEST_TIMEOUT = 5

module Minitest
  class Test
    # Helper to run async code in tests
    def async(&block)
      Async { block.call }
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
