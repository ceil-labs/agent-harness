# frozen_string_literal: true

# Integration test helper - loads main test helper and adds integration-specific setup
require_relative "../test_helper"
require_relative "../../lib/observability/null_observability"
require_relative "../support/mock_telegram"
require_relative "../support/mock_llm"
require_relative "../fixtures/telegram_messages"

module AgentHarness
  module Test
    # Integration test base class with common helpers
    class IntegrationTest < Minitest::Test
      # Setup WebMock for all integration tests
      def setup
        super
        WebMock.reset!
        WebMock.disable_net_connect!(allow_localhost: true)
      end

      def teardown
        WebMock.reset!
        super
      end

      # Create a mock secrets provider
      # @param secrets [Hash] Secret values to return
      def mock_secrets(secrets = {})
        defaults = {
          "kimi_coding.api_key" => "mock_kimi_key",
          "opencode_go.api_key" => "mock_opencode_key",
          "telegram.bot_token" => "mock_telegram_token"
        }
        all_secrets = defaults.merge(secrets)
        
        MockSecretsProvider.new(all_secrets)
      end

      # Create a standard test message
      def test_message(text = "Hello, agent!")
        {
          id: "msg-#{Time.now.to_i}",
          text: text,
          chat_id: 81_540_425_16,
          sender_id: 81_540_425_16,
          timestamp: Time.now.utc.iso8601,
          metadata: {}
        }
      end

      # Stub Kimi API HTTP requests
      def stub_kimi_api(response_body:, status: 200)
        stub_request(:post, "https://api.kimi.com/coding/v1/messages")
          .to_return(
            status: status,
            body: response_body.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      # Stub OpenCode-go API HTTP requests
      def stub_opencode_api(response_body:, status: 200)
        stub_request(:post, "https://opencode.ai/zen/go/v1/chat/completions")
          .to_return(
            status: status,
            body: response_body.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      # Stub Telegram API requests
      def stub_telegram_api(method:, response_body:, status: 200)
        stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/#{method}})
          .to_return(
            status: status,
            body: response_body.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      # Build a Kimi API success response
      def kimi_success_response(content:, input_tokens: 10, output_tokens: 15)
        {
          content: [
            { type: "text", text: content }
          ],
          stop_reason: "end_turn",
          usage: {
            input_tokens: input_tokens,
            output_tokens: output_tokens
          }
        }
      end

      # Build an OpenCode-go API success response
      def opencode_success_response(content:, prompt_tokens: 10, completion_tokens: 15)
        {
          choices: [
            {
              message: {
                role: "assistant",
                content: content
              },
              finish_reason: "stop"
            }
          ],
          usage: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: prompt_tokens + completion_tokens
          }
        }
      end

      # Build a tool call response for Kimi
      def kimi_tool_response(tool_name:, arguments:)
        {
          content: [
            {
              type: "tool_use",
              name: tool_name,
              input: arguments
            }
          ],
          stop_reason: "tool_use",
          usage: { input_tokens: 20, output_tokens: 10 }
        }
      end

      # Build a tool call response for OpenCode-go
      def opencode_tool_response(tool_name:, arguments:)
        {
          choices: [
            {
              message: {
                role: "assistant",
                tool_calls: [
                  {
                    function: {
                      name: tool_name,
                      arguments: arguments.to_json
                    }
                  }
                ]
              },
              finish_reason: "tool_calls"
            }
          ],
          usage: { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 }
        }
      end

      # Build an API error response
      def api_error_response(message: "Invalid API key", code: 401)
        {
          error: {
            message: message,
            type: "authentication_error",
            code: code
          }
        }
      end

      # Wait for async operations to complete
      def wait_for_async(timeout: 2.0)
        deadline = Time.now + timeout
        while Time.now < deadline
          yield and return true
          sleep 0.01
        end
        false
      end

      # Wait for condition with timeout (alias for compatibility)
      def wait_for(timeout: 2.0, interval: 0.01)
        deadline = Time.now + timeout
        until yield
          raise Timeout::Error, "Condition not met within #{timeout}s" if Time.now > deadline
          sleep interval
        end
      end
    end

    # Simple mock secrets provider
    class MockSecretsProvider
      def initialize(secrets)
        @secrets = secrets
      end

      def get(key)
        value = @secrets[key]
        raise AgentHarness::Secrets::SecretNotFoundError, "Secret not found: #{key}" if value.nil?
        value
      end

      def exists?(key)
        @secrets.key?(key) && !@secrets[key].nil?
      end
    end
  end
end
