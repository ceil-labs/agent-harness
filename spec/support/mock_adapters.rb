# frozen_string_literal: true

# Minimal mock implementations for harness unit tests

class SimpleMockInputAdapter
  include AgentHarness::InputAdapter

  def initialize(messages: [])
    @messages = messages
    @listeners = []
    @stopped = false
  end

  def listen(&block)
    @listeners << block
    # Don't auto-inject; wait for inject_message calls
  end

  def inject_message(message)
    @listeners.each { |l| l.call(message) }
  end

  def stop
    @stopped = true
  end

  def stopped?
    @stopped
  end
end

class SimpleMockOutputAdapter
  include AgentHarness::OutputAdapter

  attr_reader :messages

  def initialize
    @messages = []
  end

  def send(message, context: {})
    @messages << { text: message, chat_id: context[:chat_id] }
    { success: true, message_id: "mock-#{@messages.length}" }
  end

  def supports_streaming?
    false
  end

  def stream(chunk, context:, finished: false); end
end

# Minimal mock LLM for harness unit tests
# Returns proper structure with finish_reason: "stop"
class SimpleMockLLM
  include AgentHarness::LLMProvider

  attr_reader :call_count, :available_call_count, :available_lightweight_calls

  def initialize(responses: {}, raise_error: false, available_return: true)
    @responses = responses
    @raise_error = raise_error
    @call_count = 0
    @available_call_count = 0
    @available_lightweight_calls = 0
    @available_return = available_return
  end

  def generate(messages, tools: [], &block)
    @call_count += 1

    raise AgentHarness::LLMError, "Mock LLM error" if @raise_error

    last_message = messages.last[:content]
    @responses[last_message] || {
      content: "Mock response",
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
      finish_reason: "stop"
    }
  end

  def available?(lightweight: false)
    @available_call_count += 1
    if lightweight
      @available_lightweight_calls += 1
    end
    @available_return
  end

  def name
    "mock"
  end

  def model
    "mock-model"
  end
end
