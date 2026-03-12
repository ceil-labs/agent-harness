# frozen_string_literal: true

require "minitest/autorun"

module AgentHarness
  module Test
    # Contract tests for LLMProvider implementations.
    # Include this module in your adapter test class and define
    # `setup_provider` to return an instance of your provider.
    #
    # Example:
    #   class KimiCodingLLMTest < Minitest::Test
    #     include AgentHarness::Test::LLMProviderContract
    #
    #     def setup_provider
    #       AgentHarness::Adapters::KimiCodingLLM.new(...)
    #     end
    #   end
    #
    module LLMProviderContract
      def setup
        @provider = setup_provider
        @test_messages = [
          { role: "user", content: "Hello, are you working?" }
        ]
      end

      def test_implements_generate
        assert_respond_to @provider, :generate
      end

      def test_implements_available_predicate
        assert_respond_to @provider, :available?
      end

      def test_implements_name
        assert_respond_to @provider, :name
      end

      def test_implements_model
        assert_respond_to @provider, :model
      end

      def test_available_returns_boolean
        result = @provider.available?
        assert [true, false].include?(result), "available? must return boolean"
      end

      def test_name_returns_string
        result = @provider.name
        assert result.is_a?(String), "name must return String"
        refute result.empty?, "name must not be empty"
      end

      def test_model_returns_string
        result = @provider.model
        assert result.is_a?(String), "model must return String"
        refute result.empty?, "model must not be empty"
      end

      def test_generate_returns_result_hash
        skip "Requires valid API credentials" unless @provider.available?
        
        result = @provider.generate(@test_messages)
        
        assert result.is_a?(Hash)
        assert result.key?(:content) || result.key?(:tool_calls),
          "Result must have :content or :tool_calls"
        assert result.key?(:usage), "Result must have :usage"
        assert result.key?(:finish_reason), "Result must have :finish_reason"
      end

      def test_generate_usage_has_required_keys
        skip "Requires valid API credentials" unless @provider.available?
        
        result = @provider.generate(@test_messages)
        usage = result[:usage]
        
        assert usage.is_a?(Hash)
        assert usage.key?(:prompt_tokens), "usage must have :prompt_tokens"
        assert usage.key?(:completion_tokens), "usage must have :completion_tokens"
        assert usage.key?(:total_tokens), "usage must have :total_tokens"
      end

      def test_generate_accepts_tools_parameter
        skip "Requires valid API credentials and tool support" unless @provider.available?
        
        tools = [
          {
            name: "test_tool",
            description: "A test tool",
            parameters: {
              type: "object",
              properties: { input: { type: "string" } }
            }
          }
        ]
        
        # Should not raise
        result = @provider.generate(@test_messages, tools: tools)
        assert result.is_a?(Hash)
      end
    end
  end
end
