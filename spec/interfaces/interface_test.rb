# frozen_string_literal: true

require_relative "../test_helper"

# Verify that bare interfaces raise NotImplementedError

class InputAdapterInterfaceTest < Minitest::Test
  def setup
    @adapter = Object.new
    @adapter.extend(AgentHarness::InputAdapter)
  end

  def test_listen_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.listen }
  end

  def test_stop_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.stop }
  end

  def test_stopped_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.stopped? }
  end
end

class OutputAdapterInterfaceTest < Minitest::Test
  def setup
    @adapter = Object.new
    @adapter.extend(AgentHarness::OutputAdapter)
  end

  def test_send_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.send("test") }
  end

  def test_supports_streaming_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.supports_streaming? }
  end

  def test_stream_raises_not_implemented
    assert_raises(NotImplementedError) { @adapter.stream("chunk", context: {}) }
  end
end

class LLMProviderInterfaceTest < Minitest::Test
  def setup
    @provider = Object.new
    @provider.extend(AgentHarness::LLMProvider)
  end

  def test_generate_raises_not_implemented
    assert_raises(NotImplementedError) { @provider.generate([]) }
  end

  def test_available_raises_not_implemented
    assert_raises(NotImplementedError) { @provider.available? }
  end

  def test_name_raises_not_implemented
    assert_raises(NotImplementedError) { @provider.name }
  end

  def test_model_raises_not_implemented
    assert_raises(NotImplementedError) { @provider.model }
  end
end
