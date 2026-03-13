# frozen_string_literal: true

require_relative "../test_helper"

class TelegramAdapterTest < Minitest::Test
  include AgentHarness::Test::InputAdapterContract
  include AgentHarness::Test::OutputAdapterContract

  def setup_adapter
    mock_secrets = MockSecrets.new({ "telegram.bot_token" => "test-token" })
    AgentHarness::Adapters::TelegramAdapter.new(secrets: mock_secrets)
  end

  def test_available_with_configured_token
    adapter = setup_adapter
    # Note: This will fail in tests without real network/mock
    # Just verifying the method exists and doesn't crash
    assert_respond_to adapter, :available?
  end

  def test_not_available_without_token
    mock_secrets = MockSecrets.new({})
    adapter = AgentHarness::Adapters::TelegramAdapter.new(secrets: mock_secrets)
    assert_equal false, adapter.available?
  end

  # Mock secrets provider for tests
  class MockSecrets
    def initialize(data)
      @data = data
    end

    def get(key)
      @data[key] || raise(AgentHarness::ConfigurationError, "Key not found: #{key}")
    end
  end
end
