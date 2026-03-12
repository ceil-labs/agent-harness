# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/observability/logger"

class LoggerTest < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = AgentHarness::Logger.new(level: :debug, output: @output)
  end

  def teardown
    @logger.close
  end

  def test_initializes_with_defaults
    logger = AgentHarness::Logger.new
    assert_equal :info, logger.level
    assert_equal $stdout, logger.output
    assert_nil logger.file_path
    logger.close
  end

  def test_initializes_with_custom_options
    logger = AgentHarness::Logger.new(level: :debug, output: @output, file_path: "/tmp/test.log")
    assert_equal :debug, logger.level
    assert_equal @output, logger.output
    assert_equal "/tmp/test.log", logger.file_path
    logger.close
  end

  def test_logs_info_event
    @logger.info("test.event", { key: "value" })

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal "info", parsed["level"]
    assert_equal "test.event", parsed["event"]
    assert_equal({ "key" => "value" }, parsed["context"])
    assert parsed["timestamp"]
    assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, parsed["timestamp"])
  end

  def test_logs_debug_event
    @logger.debug("test.debug", { foo: "bar" })

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal "debug", parsed["level"]
    assert_equal "test.debug", parsed["event"]
  end

  def test_logs_warn_event
    @logger.warn("test.warning", { alert: true })

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal "warn", parsed["level"]
    assert_equal "test.warning", parsed["event"]
  end

  def test_logs_error_event
    @logger.error("test.error", { message: "something failed" })

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal "error", parsed["level"]
    assert_equal "test.error", parsed["event"]
  end

  def test_logs_fatal_event
    @logger.fatal("test.fatal", { critical: true })

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal "fatal", parsed["level"]
    assert_equal "test.fatal", parsed["event"]
  end

  def test_respects_log_level_debug
    logger = AgentHarness::Logger.new(level: :debug, output: @output)

    logger.debug("should.log", {})
    logger.info("should.also.log", {})

    lines = @output.string.split("\n")
    assert_equal 2, lines.length
    logger.close
  end

  def test_respects_log_level_info
    logger = AgentHarness::Logger.new(level: :info, output: @output)

    logger.debug("should.not.log", {})
    logger.info("should.log", {})
    logger.warn("should.also.log", {})

    lines = @output.string.split("\n")
    assert_equal 2, lines.length

    parsed = JSON.parse(lines[0])
    assert_equal "info", parsed["level"]
    logger.close
  end

  def test_respects_log_level_error
    logger = AgentHarness::Logger.new(level: :error, output: @output)

    logger.debug("should.not.log", {})
    logger.info("should.not.log", {})
    logger.warn("should.not.log", {})
    logger.error("should.log", {})
    logger.fatal("should.also.log", {})

    lines = @output.string.split("\n")
    assert_equal 2, lines.length
    logger.close
  end

  def test_level_enabled_predicate
    logger = AgentHarness::Logger.new(level: :warn, output: @output)

    refute logger.level_enabled?(:debug)
    refute logger.level_enabled?(:info)
    assert logger.level_enabled?(:warn)
    assert logger.level_enabled?(:error)
    assert logger.level_enabled?(:fatal)
    logger.close
  end

  def test_handles_empty_context
    @logger.info("test.event")

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal({}, parsed["context"])
  end

  def test_handles_nested_context
    context = {
      user: { id: 123, name: "test" },
      request: { path: "/test", method: "GET" }
    }
    @logger.info("test.nested", context)

    log_line = @output.string
    parsed = JSON.parse(log_line)

    assert_equal 123, parsed["context"]["user"]["id"]
    assert_equal "test", parsed["context"]["user"]["name"]
    assert_equal "/test", parsed["context"]["request"]["path"]
  end

  def test_logs_to_file
    require "tempfile"

    Tempfile.create(["test", ".log"]) do |file|
      file.close
      logger = AgentHarness::Logger.new(level: :info, output: @output, file_path: file.path)
      logger.info("file.test", { data: "value" })
      logger.close

      file_content = File.read(file.path)
      parsed = JSON.parse(file_content.strip)

      assert_equal "file.test", parsed["event"]
      assert_equal "value", parsed["context"]["data"]
    end
  end

  def test_matches_null_logger_interface
    null_logger = AgentHarness::NullLogger.new
    real_logger = AgentHarness::Logger.new(level: :debug, output: @output)

    # Ensure all methods exist on both
    assert null_logger.respond_to?(:debug)
    assert null_logger.respond_to?(:info)
    assert null_logger.respond_to?(:warn)
    assert null_logger.respond_to?(:error)

    assert real_logger.respond_to?(:debug)
    assert real_logger.respond_to?(:info)
    assert real_logger.respond_to?(:warn)
    assert real_logger.respond_to?(:error)

    # Ensure methods accept same signatures
    null_logger.info("test", { key: "value" })
    real_logger.info("test", { key: "value" })

    real_logger.close
  end
end
