# frozen_string_literal: true

module AgentHarness
  # Interface for output adapters (Telegram, Console, etc.)
  # All output adapters must implement these methods.
  module OutputAdapter
    # Send a message to the destination.
    #
    # @param message [String] The message content to send
    # @param context [Hash] Context for the message:
    #   - chat_id: [Integer] Destination chat/channel ID
    #   - message_id: [String, nil] ID of message being replied to (optional)
    #   - metadata: [Hash] Adapter-specific data (optional)
    #
    # @return [Hash] Result with at minimum:
    #   - success: [Boolean] Whether send succeeded
    #   - message_id: [String, nil] ID of sent message (if available)
    #
    # @raise [NotImplementedError] if not implemented by subclass
    def send(message, context: {})
      raise NotImplementedError, "#{self.class} must implement #send"
    end

    # Check if this adapter supports streaming responses.
    # Streaming allows sending partial content as it becomes available.
    #
    # @return [Boolean] true if streaming is supported
    # @raise [NotImplementedError] if not implemented by subclass
    def supports_streaming?
      raise NotImplementedError, "#{self.class} must implement #supports_streaming?"
    end

    # Send a streaming chunk to the destination.
    # Only called if supports_streaming? returns true.
    #
    # @param chunk [String] Partial message content
    # @param context [Hash] Same context as #send
    # @param finished [Boolean] true if this is the final chunk
    #
    # @return [void]
    # @raise [NotImplementedError] if not implemented by subclass
    def stream(chunk, context:, finished: false)
      raise NotImplementedError, "#{self.class} must implement #stream"
    end
  end
end
