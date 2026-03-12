# frozen_string_literal: true

require "minitest/autorun"

module AgentHarness
  module Test
    # Contract tests for InputAdapter implementations.
    # Include this module in your adapter test class and define
    # `setup_adapter` to return an instance of your adapter.
    #
    # Example:
    #   class TelegramAdapterTest < Minitest::Test
    #     include AgentHarness::Test::InputAdapterContract
    #
    #     def setup_adapter
    #       AgentHarness::Adapters::TelegramAdapter.new(...)
    #     end
    #   end
    #
    module InputAdapterContract
      def setup
        @adapter = setup_adapter
      end

      def test_implements_listen
        assert_respond_to @adapter, :listen
      end

      def test_implements_stop
        assert_respond_to @adapter, :stop
      end

      def test_implements_stopped_predicate
        assert_respond_to @adapter, :stopped?
      end

      def test_listen_yields_message_hash
        # Adapter should yield a hash with required keys
        received = nil
        
        # Use a timeout since listen is blocking
        Timeout.timeout(0.1) do
          @adapter.listen { |msg| received = msg; @adapter.stop }
        end
      rescue Timeout::Error
        # Expected if no messages arrive
      end

      def test_stop_sets_stopped_flag
        @adapter.stop
        assert @adapter.stopped?
      end

      def test_message_hash_has_required_keys
        skip "Requires mock message injection" unless respond_to?(:inject_test_message)
        
        received = nil
        inject_test_message("test message")
        
        Timeout.timeout(0.1) do
          @adapter.listen { |msg| received = msg; @adapter.stop }
        end

        assert received.is_a?(Hash)
        assert received.key?(:id), "Message must have :id"
        assert received.key?(:text), "Message must have :text"
        assert received.key?(:chat_id), "Message must have :chat_id"
        assert received.key?(:timestamp), "Message must have :timestamp"
        
        assert received[:id].is_a?(String)
        assert received[:text].is_a?(String)
        assert received[:chat_id].is_a?(Integer)
        assert received[:timestamp].is_a?(String)
      rescue Timeout::Error
        flunk "Message not received within timeout"
      end
    end
  end
end
