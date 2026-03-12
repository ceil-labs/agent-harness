# frozen_string_literal: true

module AgentHarness
  # Interface for input adapters (Telegram, WebSocket, etc.)
  # All input adapters must implement these methods.
  module InputAdapter
    # Start listening for incoming messages.
    # Yields a message hash to the block for each incoming message.
    #
    # @yieldparam message [Hash] Standardized message format:
    #   - id: [String] Unique message identifier
    #   - text: [String] Message content
    #   - chat_id: [Integer] Destination chat/channel ID
    #   - sender_id: [Integer, nil] Sender identifier (optional)
    #   - timestamp: [String] ISO 8601 formatted timestamp
    #   - metadata: [Hash] Adapter-specific data (optional)
    #
    # @return [void]
    # @raise [NotImplementedError] if not implemented by subclass
    def listen(&block)
      raise NotImplementedError, "#{self.class} must implement #listen"
    end

    # Gracefully stop listening for messages.
    # Should clean up any resources (connections, tasks, etc.).
    #
    # @return [void]
    # @raise [NotImplementedError] if not implemented by subclass
    def stop
      raise NotImplementedError, "#{self.class} must implement #stop"
    end

    # Check if the adapter has been stopped.
    #
    # @return [Boolean] true if stopped, false if still listening
    # @raise [NotImplementedError] if not implemented by subclass
    def stopped?
      raise NotImplementedError, "#{self.class} must implement #stopped?"
    end
  end
end
