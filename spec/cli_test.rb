# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("cli-test")
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_secrets_init_creates_master_key
    key = AgentHarness::Secrets::FileProvider.init(master_key_path: "config/master.key")

    assert File.exist?("config/master.key")
    assert File.stat("config/master.key").mode & 0o600
    assert_equal 44, key.length  # Base64 of 32 bytes = 44 chars
  end

  def test_secrets_list_shows_empty_message
    AgentHarness::Secrets::FileProvider.init(master_key_path: "config/master.key")

    provider = AgentHarness::Secrets::FileProvider.new(
      master_key_path: "config/master.key",
      secrets_path: "config/secrets.yml.enc"
    )

    names = provider.list
    assert_equal [], names
  end

  def test_secrets_list_shows_names
    AgentHarness::Secrets::FileProvider.init(master_key_path: "config/master.key")

    provider = AgentHarness::Secrets::FileProvider.new(
      master_key_path: "config/master.key",
      secrets_path: "config/secrets.yml.enc"
    )

    secrets = { "telegram" => { "token" => "test" }, "openai" => { "key" => "test" } }
    provider.send(:encrypt_file, YAML.dump(secrets))

    names = provider.list
    assert_includes names, "telegram.token"
    assert_includes names, "openai.key"
  end
end
