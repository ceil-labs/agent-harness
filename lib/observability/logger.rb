# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module AgentHarness
  # JSON structured logger for production observability
  # Writes to stdout (for Docker/container visibility) and optionally to file
  #
  # Example output:
  #   {"timestamp":"2026-03-12T10:00:00Z","level":"info","event":"harness.started","context":{"agent_id":"bot-001"}}
  class Logger
    # Standard log levels
    LEVELS = %i[debug info warn error fatal].freeze
    LEVEL_SEVERITY = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      fatal: 4
    }.freeze

    attr_reader :level, :output, :file_path

    # @param level [Symbol] Minimum log level (:debug, :info, :warn, :error, :fatal)
    # @param output [IO] Output stream (default: STDOUT)
    # @param file_path [String, nil] Optional file path for dual logging
    def initialize(level: :info, output: $stdout, file_path: nil)
      @level = level.to_sym
      @output = output
      @file_path = file_path
      @file = nil
      @mutex = Mutex.new

      open_file if @file_path
    end

    # Log at debug level
    # @param event [String] Event name (e.g., "harness.started")
    # @param context [Hash] Additional context data
    def debug(event, context = {})
      log(:debug, event, context)
    end

    # Log at info level
    # @param event [String] Event name (e.g., "harness.started")
    # @param context [Hash] Additional context data
    def info(event, context = {})
      log(:info, event, context)
    end

    # Log at warn level
    # @param event [String] Event name (e.g., "harness.slow_response")
    # @param context [Hash] Additional context data
    def warn(event, context = {})
      log(:warn, event, context)
    end

    # Log at error level
    # @param event [String] Event name (e.g., "harness.error")
    # @param context [Hash] Additional context data
    def error(event, context = {})
      log(:error, event, context)
    end

    # Log at fatal level
    # @param event [String] Event name (e.g., "harness.critical_failure")
    # @param context [Hash] Additional context data
    def fatal(event, context = {})
      log(:fatal, event, context)
    end

    # Check if a level is enabled
    # @param level [Symbol] Level to check
    # @return [Boolean]
    def level_enabled?(check_level)
      LEVEL_SEVERITY[check_level.to_sym] >= LEVEL_SEVERITY[@level]
    end

    # Close file handles and cleanup
    def close
      @mutex.synchronize do
        @file&.close
        @file = nil
      end
    end

    private

    def open_file
      @mutex.synchronize do
        FileUtils.mkdir_p(File.dirname(@file_path))
        @file = File.open(@file_path, "a")
        @file.sync = true # Flush immediately for real-time visibility
      end
    rescue => e
      @output.puts({
        timestamp: Time.now.utc.iso8601,
        level: "error",
        event: "logger.file_open_failed",
        context: { file_path: @file_path, error: e.message }
      }.to_json)
    end

    def log(severity, event, context)
      return unless level_enabled?(severity)

      entry = {
        timestamp: Time.now.utc.iso8601,
        level: severity.to_s,
        event: event,
        context: context || {}
      }

      json_line = entry.to_json

      @mutex.synchronize do
        @output.puts(json_line)
        @file&.puts(json_line)
      end
    end
  end
end
