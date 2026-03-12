# frozen_string_literal: true

module AgentHarness
  # Interface for LLM providers (Kimi, MiniMax, OpenAI, Grok)
  # All LLM providers must implement these methods.
  module LLMProvider
    # Generate a completion from the LLM.
    #
    # @param messages [Array<Hash>] Conversation history:
    #   - role: [String] "user", "assistant", or "system"
    #   - content: [String] Message content
    # @param tools [Array<Hash>] Tool definitions for function calling (optional)
    #   - name: [String] Tool name
    #   - description: [String] Tool description
    #   - parameters: [Hash] JSON schema for parameters
    # @yieldparam chunk [String] Streaming chunk (if provider supports streaming)
    #
    # @return [Hash] Completion result:
    #   - content: [String, nil] Generated text (nil if tool_calls present)
    #   - tool_calls: [Array<Hash>] Tool invocations (optional):
    #     - name: [String] Tool name
    #     - arguments: [Hash] Parsed arguments
    #   - usage: [Hash] Token usage statistics:
    #     - prompt_tokens: [Integer]
    #     - completion_tokens: [Integer]
    #     - total_tokens: [Integer]
    #   - finish_reason: [String] "stop", "tool_calls", "length", etc.
    #
    # @raise [NotImplementedError] if not implemented by subclass
    def generate(messages, tools: [], &block)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end

    # Check if the provider is configured and available.
    # Used for health checks and provider selection.
    #
    # @return [Boolean] true if provider is ready to use
    # @raise [NotImplementedError] if not implemented by subclass
    def available?
      raise NotImplementedError, "#{self.class} must implement #available?"
    end

    # Get provider name/identifier.
    # Used for logging and metrics.
    #
    # @return [String] Provider name (e.g., "kimi_coding", "openai")
    # @raise [NotImplementedError] if not implemented by subclass
    def name
      raise NotImplementedError, "#{self.class} must implement #name"
    end

    # Get the model identifier.
    # Used for logging and metrics.
    #
    # @return [String] Model name (e.g., "kimi-coding/k2p5", "gpt-4o-mini")
    # @raise [NotImplementedError] if not implemented by subclass
    def model
      raise NotImplementedError, "#{self.class} must implement #model"
    end
  end
end
