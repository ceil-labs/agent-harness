# frozen_string_literal: true

require "minitest/autorun"

module AgentHarness
  module Test
    # Contract tests for OutputAdapter implementations.
    # Include this module in your adapter test class and define
    # `setup_adapter` to return an instance of your adapter.
    #
    # Example:
    #   class TelegramAdapterTest < Minitest::Test
    #     include AgentHarness::Test::OutputAdapterContract
    #
    #     def setup_adapter
    #       AgentHarness::Adapters::TelegramAdapter.new(...)
    #     end
    #   end
    #
    module OutputAdapterContract
      def setup
        @adapter = setup_adapter
        @test_context = { chat_id: 123456789 }
      end

      def test_implements_send
        assert_respond_to @adapter, :send
      end

      def test_implements_supports_streaming_predicate
        assert_respond_to @adapter, :supports_streaming?
      end

      def test_implements_stream
        assert_respond_to @adapter, :stream
      end

      def test_send_returns_result_hash
        skip "Requires mock output destination" unless respond_to?(:mock_send_destination)
        
        result = @adapter.send("Hello, World!", context: @test_context)
        
        assert result.is_a?(Hash)
        assert result.key?(:success), "Result must have :success"
        assert [true, false].include?(result[:success]), ":success must be boolean"
      end

      def test_supports_streaming_returns_boolean
        result = @adapter.supports_streaming?
        assert [true, false].include?(result), "supports_streaming? must return boolean"
      end

      def test_send_requires_message_parameter
        assert_raises(ArgumentError) { @adapter.send(context: @test_context) }
      end

      def test_send_accepts_context_parameter
        # Should not raise when context is provided
        mock_send_destination if respond_to?(:mock_send_destination)
        
        result = @adapter.send("Test", context: @test_context)
        assert result.is_a?(Hash)
      end
    end
  end
end
