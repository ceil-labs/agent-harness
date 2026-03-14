# frozen_string_literal: true

module AgentHarness
  module Test
    # Mock LLM provider for integration testing
    # Simulates responses from Kimi Coding and OpenCode-go APIs
    class MockLLMProvider
      include AgentHarness::LLMProvider

      attr_reader :call_count, :last_messages, :last_tools, :responses
      attr_accessor :raise_error, :delay_ms

      # @param provider_type [Symbol] :kimi_coding or :opencode_go
      # @param model [String] Model identifier
      # @param responses [Hash] Pre-configured responses keyed by message content
      def initialize(provider_type: :kimi_coding, model: nil, responses: {})
        @provider_type = provider_type
        @model = model || default_model
        @responses = responses
        @call_count = 0
        @last_messages = nil
        @last_tools = nil
        @raise_error = false
        @delay_ms = 0
        @available = true
      end

      # Generate a completion response
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool definitions (optional)
      # @return [Hash] Standardized response
      def generate(messages, tools: [], &block)
        @call_count += 1
        @last_messages = messages
        @last_tools = tools

        # Simulate network delay if configured
        sleep(@delay_ms / 1000.0) if @delay_ms > 0

        # Raise error if configured
        raise AgentHarness::LLMError, "Mock LLM error" if @raise_error

        # Get the last user message to look up response
        last_message = messages.reverse.find { |m| m[:role] == "user" }
        query = last_message ? last_message[:content] : ""

        # Check for pre-configured response
        if @responses.key?(query)
          return @responses[query]
        end

        # Check for partial match in responses
        @responses.each do |key, response|
          return response if query.include?(key)
        end

        # Return default response
        default_response(query)
      end

      # Check if provider is available
      # @param lightweight [Boolean] If true, skip network check
      # @return [Boolean]
      def available?(lightweight: false)
        @available
      end

      def available=(value)
        @available = value
      end

      # Get provider name
      # @return [String]
      def name
        @provider_type.to_s
      end

      # Get model identifier
      # @return [String]
      def model
        @model
      end

      # Configure a response for a specific query
      # @param query [String] Message content to match
      # @param response [Hash] Response to return
      def stub_response(query, response)
        @responses[query] = response
      end

      # Stub a successful text response
      # @param query [String] Message to match
      # @param content [String] Response content
      # @param options [Hash] Additional options
      def stub_success(query, content, options = {})
        stub_response(query, build_success_response(content, options))
      end

      # Stub a tool call response
      # @param query [String] Message to match
      # @param tool_name [String] Name of tool to call
      # @param arguments [Hash] Tool arguments
      def stub_tool_call(query, tool_name, arguments = {})
        stub_response(query, build_tool_response(tool_name, arguments))
      end

      # Stub an error response
      # @param query [String] Message to match (or :any for all)
      def stub_error(query = :any)
        if query == :any
          @raise_error = true
        else
          stub_response(query, build_error_response)
        end
      end

      # Reset all stubs and counters
      def reset
        @call_count = 0
        @last_messages = nil
        @last_tools = nil
        @raise_error = false
        @responses.clear
      end

      # Build a success response in the appropriate format
      def build_success_response(content, options = {})
        {
          content: content,
          usage: options[:usage] || default_usage,
          finish_reason: options[:finish_reason] || "stop",
          tool_calls: nil
        }
      end

      # Build a tool call response
      def build_tool_response(tool_name, arguments = {})
        {
          content: nil,
          usage: default_usage,
          finish_reason: "tool_calls",
          tool_calls: [
            {
              name: tool_name,
              arguments: arguments
            }
          ]
        }
      end

      # Build an error response
      def build_error_response(error_message = "Mock LLM error")
        {
          content: nil,
          usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
          finish_reason: "error",
          error: error_message
        }
      end

      private

      def default_model
        case @provider_type
        when :kimi_coding
          "k2p5"
        when :opencode_go
          "glm-5"
        else
          "mock-model"
        end
      end

      def default_usage
        {
          prompt_tokens: 10,
          completion_tokens: 15,
          total_tokens: 25
        }
      end

      def default_response(query)
        build_success_response("Mock response to: #{query[0..50]}")
      end
    end

    # Factory for creating provider-specific mocks
    class MockLLMFactory
      # Create a Kimi Coding mock
      def self.kimi_coding(model: "k2p5", **options)
        MockLLMProvider.new(provider_type: :kimi_coding, model: model, **options)
      end

      # Create an OpenCode-go mock with GLM-5
      def self.opencode_go_glm5(**options)
        MockLLMProvider.new(provider_type: :opencode_go, model: "glm-5", **options)
      end

      # Create an OpenCode-go mock with Kimi
      def self.opencode_go_kimi(**options)
        MockLLMProvider.new(provider_type: :opencode_go, model: "kimi-k2.5", **options)
      end

      # Create an OpenCode-go mock with MiniMax
      def self.opencode_go_minimax(**options)
        MockLLMProvider.new(provider_type: :opencode_go, model: "minimax-m2.5", **options)
      end
    end
  end
end
