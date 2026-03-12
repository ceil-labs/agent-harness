# frozen_string_literal: true

require "async"
require "async/http/internet/instance"
require "json"

module AgentHarness
  module Adapters
    # Kimi Coding LLM adapter for agent-harness
    # Uses Moonshot AI API with Anthropic-compatible format
    # Endpoint: https://api.kimi.com/coding/v1/messages
    #
    # Example usage:
    #   secrets = AgentHarness::Secrets::FileProvider.new(
    #     master_key_path: "/path/to/master.key",
    #     secrets_path: "/path/to/secrets.yml.enc"
    #   )
    #   llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)
    #   response = llm.generate([{ role: "user", content: "Hello" }])
    #   # => { content: "Hi!", usage: {...}, finish_reason: "stop" }
    #
    class KimiCodingLLM
      include AgentHarness::LLMProvider

      API_ENDPOINT = "https://api.kimi.com/coding/v1/messages"
      DEFAULT_MODEL = "k2p5"
      TIMEOUT_SECONDS = 60

      # @param secrets [AgentHarness::Secrets::FileProvider] Secrets provider
      # @param model [String] Model identifier (defaults to kimi-coding/k2p5)
      # @param timeout [Integer] Request timeout in seconds
      def initialize(secrets:, model: DEFAULT_MODEL, timeout: TIMEOUT_SECONDS)
        @secrets = secrets
        @model = model
        @timeout = timeout
      end

      # Generate a completion from the Kimi API
      #
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool definitions for function calling (optional)
      # @yieldparam chunk [String] Streaming chunk (not yet implemented)
      # @return [Hash] Completion result with :content, :usage, :finish_reason
      def generate(messages, tools: [], &block)
        Async do
          response = post_to_api(messages, tools)
          parse_response(response)
        end.wait
      rescue Async::Stop
        raise
      rescue => e
        handle_error(e)
      end

      # Check if the provider is configured and available
      # Makes a lightweight API call to verify connectivity
      #
      # @return [Boolean] true if API key is configured and API is reachable
      def available?
        return false unless api_key_configured?

        Async do
          # Try a minimal request to verify connectivity and authentication
          internet = Async::HTTP::Internet.new
          headers = [
            ["Authorization", "Bearer #{api_key}"],
            ["Content-Type", "application/json"]
          ]
          
          # Send a minimal test request (Anthropic format)
          body = JSON.dump({
            model: @model,
            messages: [{ role: "user", content: "Hi" }],
            max_tokens: 1
          })
          
          response = internet.post(API_ENDPOINT, headers, [body])
          response.finish
          
          # Check for successful response or client errors (4xx means API is reachable but auth failed)
          # Only 5xx errors mean the service is down
          if response.status >= 500
            false
          elsif response.status == 401 || response.status == 403
            # Invalid credentials - API is reachable but auth failed
            false
          else
            true
          end
        rescue => e
          false
        end.wait
      rescue => e
        false
      end

      # Get provider name/identifier
      #
      # @return [String] Provider name
      def name
        "kimi_coding"
      end

      # Get the model identifier
      #
      # @return [String] Model name
      def model
        @model
      end

      private

      # Check if API key is configured in secrets
      #
      # @return [Boolean]
      def api_key_configured?
        @secrets.exists?("kimi_coding.api_key")
      rescue
        false
      end

      # Get the API key from secrets
      #
      # @return [String] API key
      # @raise [AgentHarness::ConfigurationError] if key not found
      def api_key
        @secrets.get("kimi_coding.api_key")
      rescue AgentHarness::Secrets::SecretNotFoundError => e
        raise AgentHarness::ConfigurationError, "Kimi Coding API key not configured. Set kimi_coding.api_key in secrets."
      end

      # Make HTTP POST request to Kimi API
      #
      # @param messages [Array<Hash>] Messages to send
      # @param tools [Array<Hash>] Tool definitions
      # @return [String] Response body
      def post_to_api(messages, tools = [])
        internet = Async::HTTP::Internet.new
        
        headers = [
          ["Authorization", "Bearer #{api_key}"],
          ["Content-Type", "application/json"]
        ]

        body = build_request_body(messages, tools)
        
        response = internet.post(API_ENDPOINT, headers, [JSON.dump(body)])
        response.read
      ensure
        internet&.close
      end

      # Build the request body for the API (Anthropic-compatible format)
      #
      # @param messages [Array<Hash>] Messages
      # @param tools [Array<Hash>] Tool definitions
      # @return [Hash] Request body
      def build_request_body(messages, tools)
        # Separate system message from conversation
        system_message = messages.find { |m| m[:role] == "system" }
        conversation = messages.reject { |m| m[:role] == "system" }

        body = {
          model: @model,
          messages: conversation,
          max_tokens: 4096
        }

        # Add system prompt if present
        if system_message
          body[:system] = system_message[:content]
        end

        # Add tools if provided (Anthropic format)
        if tools && !tools.empty?
          body[:tools] = tools.map { |t| format_tool(t) }
        end

        body
      end

      # Format a tool definition for Anthropic API
      #
      # @param tool [Hash] Tool definition
      # @return [Hash] Formatted tool
      def format_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          input_schema: tool[:parameters]
        }
      end

      # Parse the API response (Anthropic-compatible format)
      #
      # @param response_body [String] Raw response body
      # @return [Hash] Parsed response with standardized keys
      def parse_response(response_body)
        data = JSON.parse(response_body, symbolize_names: true)

        # Check for API errors
        if data[:error]
          raise AgentHarness::LLMError, "Kimi API error: #{data[:error][:message]}"
        end

        # Anthropic format: content is an array of content blocks
        content_blocks = data[:content] || []
        text_content = content_blocks
          .select { |block| block[:type] == "text" }
          .map { |block| block[:text] }
          .join

        # Check for tool_use blocks
        tool_use_blocks = content_blocks.select { |block| block[:type] == "tool_use" }

        # Build standardized response
        result = {
          content: text_content.empty? ? nil : text_content,
          usage: extract_usage(data[:usage]),
          finish_reason: data[:stop_reason]&.to_s
        }

        # Handle tool calls if present
        if tool_use_blocks.any?
          result[:tool_calls] = tool_use_blocks.map do |tc|
            {
              name: tc[:name],
              arguments: tc[:input] || {}
            }
          end
          result[:content] = nil  # Content is nil when tool_calls are present
        end

        result
      rescue JSON::ParserError => e
        raise AgentHarness::LLMError, "Failed to parse Kimi API response: #{e.message}"
      end

      # Extract usage statistics from API response (Anthropic format)
      #
      # @param usage [Hash] Usage data from API
      # @return [Hash] Standardized usage
      def extract_usage(usage)
        return { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 } unless usage

        {
          prompt_tokens: usage[:input_tokens] || 0,
          completion_tokens: usage[:output_tokens] || 0,
          total_tokens: (usage[:input_tokens] || 0) + (usage[:output_tokens] || 0)
        }
      end

      # Parse tool call arguments from string or hash
      #
      # @param args [String, Hash] Arguments
      # @return [Hash] Parsed arguments
      def parse_tool_arguments(args)
        return {} unless args
        return args if args.is_a?(Hash)

        JSON.parse(args, symbolize_names: true)
      rescue JSON::ParserError
        { raw: args }
      end

      # Handle errors and return appropriate response or raise
      #
      # @param error [Exception] The error that occurred
      # @return [Hash] Error response hash
      # @raise [AgentHarness::LLMError] for certain error types
      def handle_error(error)
        case error
        when AgentHarness::LLMError, AgentHarness::ConfigurationError
          raise error
        when Async::TimeoutError, Timeout::Error
          raise AgentHarness::LLMError, "Request to Kimi API timed out"
        else
          raise AgentHarness::LLMError, "Unexpected error: #{error.class} - #{error.message}"
        end
      end
    end
  end
end
