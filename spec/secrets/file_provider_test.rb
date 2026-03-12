# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/secrets/file_provider"

class FileProviderTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("secrets-test")
    @master_key_path = File.join(@temp_dir, "master.key")
    @secrets_path = File.join(@temp_dir, "secrets.yml.enc")

    # Generate master key
    @key = AgentHarness::Secrets::FileProvider.init(master_key_path: @master_key_path)

    @provider = AgentHarness::Secrets::FileProvider.new(
      master_key_path: @master_key_path,
      secrets_path: @secrets_path
    )
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_initializes_with_paths
    assert_equal @master_key_path, @provider.master_key_path
    assert_equal @secrets_path, @provider.secrets_path
  end

  def test_generate_key_creates_base64
    key = AgentHarness::Secrets::FileProvider.generate_key
    decoded = Base64.strict_decode64(key)
    assert_equal 32, decoded.bytesize  # AES-256 needs 32 bytes
  end

  def test_init_creates_key_file
    assert File.exist?(@master_key_path)
    assert File.stat(@master_key_path).mode & 0o600  # Check permissions
  end

  def test_encrypts_and_decrypts
    # Manually create encrypted secrets
    plaintext = YAML.dump({ "test_key" => "secret_value" })
    @provider.send(:encrypt_file, plaintext)

    # Should be able to decrypt
    decrypted = @provider.send(:decrypt_file)
    secrets = YAML.safe_load(decrypted)

    assert_equal "secret_value", secrets["test_key"]
  end

  def test_get_retrieves_secret
    # Create encrypted file with secret
    secrets = { "api" => { "key" => "test-api-key-12345" } }
    plaintext = YAML.dump(secrets)
    @provider.send(:encrypt_file, plaintext)

    value = @provider.get("api.key")
    assert_equal "test-api-key-12345", value
  end

  def test_get_raises_on_missing
    assert_raises(AgentHarness::Secrets::SecretNotFoundError) do
      @provider.get("nonexistent")
    end
  end

  def test_exists_returns_true_for_existing
    secrets = { "existing" => "value" }
    @provider.send(:encrypt_file, YAML.dump(secrets))

    assert @provider.exists?("existing")
    refute @provider.exists?("missing")
  end

  def test_list_returns_all_keys
    secrets = {
      "telegram" => { "token" => "abc", "chat_id" => "123" },
      "openai" => { "api_key" => "xyz" }
    }
    @provider.send(:encrypt_file, YAML.dump(secrets))

    keys = @provider.list
    assert_includes keys, "telegram.token"
    assert_includes keys, "telegram.chat_id"
    assert_includes keys, "openai.api_key"
  end

  def test_list_returns_empty_for_no_secrets
    assert_equal [], @provider.list
  end

  def test_audit_log_created
    secrets = { "sensitive" => "data" }
    @provider.send(:encrypt_file, YAML.dump(secrets))

    # Access secret
    @provider.get("sensitive")

    audit_path = File.join(@temp_dir, ".audit.log")
    assert File.exist?(audit_path)

    log_content = File.read(audit_path)
    assert_includes log_content, "sensitive"
    assert_includes log_content, "timestamp"
  end
end
