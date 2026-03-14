# frozen_string_literal: true

# VCR Configuration for recording/replaying HTTP interactions
# This file is loaded by spec/test_helper.rb

require "vcr"

VCR.configure do |config|
  # Cassette library directory
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  
  # Hook into webmock
  config.hook_into :webmock
  
  # Don't allow HTTP connections when no cassette is in use
  config.allow_http_connections_when_no_cassette = false
  
  # Re-record cassettes after 30 days
  config.default_cassette_options = {
    record: :once,
    re_record_interval: 30 * 24 * 60 * 60 # 30 days in seconds
  }
  
  # Filter sensitive data from recordings
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

# Helper module for VCR cassette management in Minitest
module VCRTestHelper
  # Use a VCR cassette for a test
  # @param cassette_name [String] Name of the cassette (without extension)
  # @param options [Hash] VCR options
  def use_vcr_cassette(cassette_name, **options)
    VCR.use_cassette(cassette_name, **options) do
      yield
    end
  end
end
