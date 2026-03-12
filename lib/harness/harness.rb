# frozen_string_literal: true

require "async"
require "async/http"

module AgentHarness
  # Null object for MessageBus - used in Phase 0 (single agent)
  # Phase 4 will replace with RedisMessageBus
  class NullMessageBus
    def publish(*); end
    def subscribe; end
    def subscribe_to_agent(agent_id); end
  end

  # Null object for AgentRegistry - used in Phase 0
  # Phase 4 will replace with RedisRegistry or Consul
  class NullRegistry
    def register(agent_id, info = {}); end
    def unregister(agent_id); end
    def discover(agent_id); nil; end
    def list; []; end
  end

  # Core harness with async supervision
  class Harness
    attr_reader :agent_id, :input, :output, :llm, :config, :logger, :metrics
    attr_reader :message_bus, :agent_registry

    # @param agent_id [String] Unique identifier for this agent instance
    # @param input [InputAdapter] Input source (Telegram, etc.)
    # @param output [OutputAdapter] Output destination (Telegram, etc.)
    # @param llm [LLMProvider] LLM provider (Kimi, OpenAI, etc.)
    # @param config [Hash] Configuration options
    # @param logger [Logger] Structured logger
    # @param metrics [Metrics] Prometheus metrics collector
    # @param message_bus [MessageBus] Phase 4: inter-agent communication (null in Phase 0)
    # @param agent_registry [AgentRegistry] Phase 4: service discovery (null in Phase 0)
    def initialize(
      agent_id:,
      input:,
      output:,
      llm:,
      config: {},
      logger: NullLogger.new,
      metrics: NullMetrics.new,
      message_bus: NullMessageBus.new,
      agent_registry: NullRegistry.new
    )
      @agent_id = agent_id
      @input = input
      @output = output
      @llm = llm
      @config = config
      @logger = logger
      @metrics = metrics
      @message_bus = message_bus
      @agent_registry = agent_registry

      @shutdown = Async::Condition.new
      @running = false
      @tasks = []
    end

    # Start the harness - blocks until stop() is called
    # @return [void]
    def start
      @running = true

      Async do |task|
        @supervisor = task

        @logger.info("harness.started", {
          agent_id: @agent_id,
          version: VERSION,
          llm_provider: @llm.name,
          llm_model: @llm.model
        })

        # Register with agent registry (Phase 4) - no-op in Phase 0
        @agent_registry.register(@agent_id, {
          started_at: Time.now.iso8601,
          llm_provider: @llm.name,
          capabilities: [:chat]
        })

        # Start input listener in separate fiber
        @tasks << task.async { listen_for_messages }

        # Start inter-agent message listener (Phase 4) - no-op in Phase 0
        @tasks << task.async { listen_for_agent_messages }

        # Start periodic health checks
        @tasks << task.async { run_health_checks }

        # Wait for shutdown signal
        @shutdown.wait

        @logger.info("harness.stopping", { agent_id: @agent_id })
      end

      @running = false
      @logger.info("harness.stopped", { agent_id: @agent_id })
    ensure
      cleanup
    end

    # Gracefully stop the harness
    # @return [void]
    def stop
      return unless @running

      @logger.info("harness.stop_requested", { agent_id: @agent_id })
      @shutdown.signal
    end

    # Check if harness is running
    # @return [Boolean]
    def running?
      @running
    end

    private

    # Main message listening loop
    def listen_for_messages
      @input.listen do |message|
        @logger.debug("harness.message_received", {
          agent_id: @agent_id,
          message_id: message[:id],
          chat_id: message[:chat_id],
          text_length: message[:text].to_s.length
        })

        @metrics.increment(:messages_total, labels: { agent_id: @agent_id })

        # Process each message in its own fiber (concurrent)
        Async { process_message(message) }
      end
    rescue => e
      @logger.error("harness.input_error", {
        agent_id: @agent_id,
        error: e.message,
        error_class: e.class.name
      })
      raise
    end

    # Process a single message through the harness
    def process_message(message)
      start_time = Time.now

      @logger.info("harness.processing_started", {
        agent_id: @agent_id,
        message_id: message[:id],
        chat_id: message[:chat_id]
      })

      # Build LLM request
      messages = build_llm_messages(message)

      # Call LLM
      response = call_llm(messages)

      # Send response (or error if LLM failed)
      if response
        @output.send(response[:content], context: message)

        @logger.info("harness.response_sent", {
          agent_id: @agent_id,
          message_id: message[:id],
          chat_id: message[:chat_id],
          response_length: response[:content].to_s.length
        })

        # Record latency
        duration = Time.now - start_time
        @metrics.observe(:llm_request_duration_seconds, duration, labels: { agent_id: @agent_id })
      else
        # LLM returned nil (error occurred)
        error_message = "Sorry, I couldn't generate a response. Please try again."
        @output.send(error_message, context: message)

        @logger.warn("harness.empty_response", {
          agent_id: @agent_id,
          message_id: message[:id]
        })
      end

    rescue => e
      handle_error(e, message)
    end

    # Build messages array for LLM
    def build_llm_messages(incoming_message)
      [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: incoming_message[:text]
        }
      ]
    end

    # System prompt for the agent
    def system_prompt
      @config[:system_prompt] || "You are a helpful assistant."
    end

    # Call LLM provider
    def call_llm(messages)
      @llm.generate(messages)
    rescue => e
      @logger.error("harness.llm_error", {
        agent_id: @agent_id,
        error: e.message,
        error_class: e.class.name
      })
      nil
    end

    # Handle errors during message processing
    def handle_error(error, message)
      @logger.error("harness.processing_error", {
        agent_id: @agent_id,
        message_id: message[:id],
        error: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.first(5)
      })

      @metrics.increment(:errors_total, labels: {
        agent_id: @agent_id,
        error_class: error.class.name
      })

      # Send error message to user
      error_message = "Sorry, an error occurred while processing your message."
      @output.send(error_message, context: message)
    rescue => e
      # Last resort logging if even error handling fails
      warn "CRITICAL: Error handler failed: #{e.message}"
    end

    # Listen for messages from other agents (Phase 4)
    # No-op in Phase 0 (NullMessageBus)
    def listen_for_agent_messages
      @message_bus.subscribe do |msg|
        handle_agent_message(msg)
      end
    rescue => e
      @logger.error("harness.agent_message_error", {
        agent_id: @agent_id,
        error: e.message
      })
    end

    # Handle messages from other agents (Phase 4)
    def handle_agent_message(msg)
      # Phase 4 implementation:
      # - Delegate task handling
      # - Request/response coordination
      # - Broadcast handling

      @logger.debug("harness.agent_message_received", {
        agent_id: @agent_id,
        from: msg[:from],
        type: msg[:type]
      })
    end

    # Periodic health checks and metrics reporting
    def run_health_checks
      interval = @config[:health_check_interval] || 60

      while @running
        sleep(interval)

        @logger.debug("harness.health_check", {
          agent_id: @agent_id,
          input_status: @input.stopped? ? "stopped" : "running",
          llm_available: @llm.available?
        })

        @metrics.gauge(:up, @running ? 1 : 0, labels: { agent_id: @agent_id })
      end
    rescue => e
      @logger.error("harness.health_check_error", {
        agent_id: @agent_id,
        error: e.message
      })
    end

    # Cleanup on shutdown
    def cleanup
      @tasks.each { |t| t.stop rescue nil }
      @tasks.clear

      @input.stop rescue nil

      @agent_registry.unregister(@agent_id) rescue nil

      @logger.info("harness.cleanup_complete", { agent_id: @agent_id })
    rescue => e
      warn "Cleanup error: #{e.message}"
    end
  end
end
