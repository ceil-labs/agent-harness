# frozen_string_literal: true

require "async"
require "async/http/internet/instance"
require "json"

module AgentHarness
  module Adapters
    # OpenCode-go LLM adapter for agent-harness
    # Uses OpenCode-go API with OpenAI-compatible format
    # Endpoint: https://api.opencode.ai/v1/chat/completions
    #
    # Supported models via OpenCode-go:
    #   - glm-5 (GLM model)
    #   - kimi-k2.5 (Kimi model)
    #   - minimax-m2.5 (MiniMax model)
    #
    # Example usage:
    #   secrets = AgentHarness::Secrets::FileProvider.new(
    #     master_key_path: "/path/to/master.key",
    #     secrets_path: "/path/to/secrets.yml.enc"
    #   )
    #   llm = AgentHarness::Adapters::OpenCodeGoLLM.new(secrets: secrets)
    #   response = llm.generate([{ role: "user", content: "Hello" }])
    #   # => { content: "Hi!", usage: {...}, finish_reason: "stop" }
    #
    class OpenCodeGoLLM
      include AgentHarness::LLMProvider

      API_ENDPOINT = "https://api.opencode.ai/v1/chat/completions"
      DEFAULT_MODEL = "kimi-k2.5"
      TIMEOUT_SECONDS = 60

      # @param secrets [AgentHarness::Secrets::FileProvider] Secrets provider
      # @param model [String] Model identifier (defaults to kimi-k2.5)
      #   Available: glm-5, kimi-k2.5, minimax-m2.5
      # @param timeout [Integer] Request timeout in seconds
      def initialize(secrets:, model: DEFAULT_MODEL, timeout: TIMEOUT_SECONDS)
        @secrets = secrets
        @model = model
        @timeout = timeout
      end

      # Generate a completion from the OpenCode-go API
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
      #
      # @param lightweight [Boolean] If true, only check API key config (no HTTP call)
      # @return [Boolean] true if API key is configured and API is reachable
      def available?(lightweight: false)
        return false unless api_key_configured?

        # Lightweight mode: just verify API key is configured
        return true if lightweight

        # Full check: make actual API call to verify connectivity
        Async do
          internet = Async::HTTP::Internet.new
          headers = [
            ["Authorization", "Bearer #{api_key}"],
            ["Content-Type", "application/json"]
          ]

          # Send a minimal test request (OpenAI format)
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
        "opencode_go"
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
        @secrets.exists?("opencode_go.api_key")
      rescue
        false
      end

      # Get the API key from secrets
      #
      # @return [String] API key
      # @raise [AgentHarness::ConfigurationError] if key not found
      def api_key
        @secrets.get("opencode_go.api_key")
      rescue AgentHarness::Secrets::SecretNotFoundError => e
        raise AgentHarness::ConfigurationError, "OpenCode-go API key not configured. Set opencode_go.api_key in secrets."
      end

      # Make HTTP POST request to OpenCode-go API
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

      # Build the request body for the API (OpenAI-compatible format)
      #
      # @param messages [Array<Hash>] Messages
      # @param tools [Array<Hash>] Tool definitions
      # @return [Hash] Request body
      def build_request_body(messages, tools)
        body = {
          model: @model,
          messages: messages,
          max_tokens: 4096
        }

        # Add tools if provided (OpenAI format)
        if tools && !tools.empty?
          body[:tools] = tools.map { |t| format_tool(t) }
        end

        body
      end

      # Format a tool definition for OpenAI API
      #
      # @param tool [Hash] Tool definition
      # @return [Hash] Formatted tool (OpenAI function format)
      def format_tool(tool)
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:parameters]
          }
        }
      end

      # Parse the API response (OpenAI-compatible format)
      #
      # @param response_body [String] Raw response body
      # @return [Hash] Parsed response with standardized keys
      def parse_response(response_body)
        data = JSON.parse(response_body, symbolize_names: true)

        # Check for API errors
        if data[:error]
          raise AgentHarness::LLMError, "OpenCode-go API error: #{data[:error][:message]}"
        end

        # OpenAI format: content is a string, tool_calls is in message
        choices = data[:choices] || []
        first_choice = choices.first

        raise AgentHarness::LLMError, "No choices in response" unless first_choice

        message = first_choice[:message] || {}

        # Build standardized response
        result = {
          content: message[:content],
          usage: extract_usage(data[:usage]),
          finish_reason: first_choice[:finish_reason]&.to_s
        }

        # Handle tool calls if present
        if message[:tool_calls] && !message[:tool_calls].empty?
          result[:tool_calls] = message[:tool_calls].map do |tc|
            {
              name: tc[:function][:name],
              arguments: parse_tool_arguments(tc[:function][:arguments])
            }
          end
          result[:content] = nil  # Content is nil when tool_calls are present
        end

        result
      rescue JSON::ParserError => e
        raise AgentHarness::LLMError, "Failed to parse OpenCode-go API response: #{e.message}"
      end

      # Extract usage statistics from API response (OpenAI format)
      #
      # @param usage [Hash] Usage data from API
      # @return [Hash] Standardized usage
      def extract_usage(usage)
        return { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 } unless usage

        prompt = usage[:prompt_tokens] || 0
        completion = usage[:completion_tokens] || 0

        {
          prompt_tokens: prompt,
          completion_tokens: completion,
          total_tokens: usage[:total_tokens] || (prompt + completion)
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
          raise AgentHarness::LLMError, "Request to OpenCode-go API timed out"
        else
          raise AgentHarness::LLMError, "Unexpected error: #{error.class} - #{error.message}"
        end
      end
    end
  end
end
