# frozen_string_literal: true

require "openssl"
require "base64"
require "yaml"
require "fileutils"
require "json"

module AgentHarness
  module Secrets
    # File-based secrets provider with AES-256-GCM encryption
    # Uses Ruby's built-in OpenSSL (no external dependencies)
    class FileProvider
      AUTH_TAG_BYTES = 16
      NONCE_BYTES = 12
      KEY_BYTES = 32

      attr_reader :master_key_path, :secrets_path

      # @param master_key_path [String] Path to master key file (32 bytes, base64)
      # @param secrets_path [String] Path to encrypted secrets YAML file
      def initialize(master_key_path:, secrets_path:)
        @master_key_path = master_key_path
        @secrets_path = secrets_path
        @audit_log = []
      end

      # Get a secret by name (dot notation supported: "telegram.bot_token")
      # @param name [String] Secret name
      # @return [String] Decrypted secret value
      # @raise [SecretNotFoundError] if secret doesn't exist
      def get(name)
        audit_access(name)

        secrets = load_secrets
        keys = name.split(".")
        value = secrets.dig(*keys)

        raise SecretNotFoundError, "Secret not found: #{name}" unless value

        decrypt(value)
      end

      # Check if secret exists
      # @param name [String] Secret name
      # @return [Boolean]
      def exists?(name)
        secrets = load_secrets
        keys = name.split(".")
        !!secrets.dig(*keys)
      rescue
        false
      end

      # List all secret names (not values)
      # @return [Array<String>] List of secret names (flattened dot notation)
      def list
        secrets = load_secrets
        flatten_keys(secrets)
      end

      # Edit secrets interactively
      # Decrypts, opens in editor, encrypts on save
      # @return [Boolean] true if saved successfully
      def edit
        require "tempfile"

        # Load existing or create new
        plaintext = File.exist?(@secrets_path) ? decrypt_file : "{}"

        # Write to secure temp file (0600 permissions, unpredictable name)
        temp_file = Tempfile.new(["agent-harness-secrets-", ".yml"])
        temp_file.write(plaintext)
        temp_file.close

        # Ensure restrictive permissions (Tempfile should be 0600, but be explicit)
        FileUtils.chmod(0o600, temp_file.path)

        # Open in editor
        editor = ENV["EDITOR"] || "nano"
        system("#{editor} #{temp_file.path}")

        # Read back and encrypt
        new_plaintext = File.read(temp_file.path)
        encrypt_file(new_plaintext)

        true
      ensure
        # Cleanup - temp_file may be nil if Tempfile.new failed
        temp_file&.close
        temp_file&.unlink
      end

      # Generate a new master key
      # @return [String] Base64-encoded 32-byte key
      def self.generate_key
        key = OpenSSL::Random.random_bytes(KEY_BYTES)
        Base64.strict_encode64(key)
      end

      # Initialize secrets directory with new master key
      # @param master_key_path [String] Where to create master key
      # @return [String] The generated key
      def self.init(master_key_path:)
        key = generate_key

        FileUtils.mkdir_p(File.dirname(master_key_path))
        File.write(master_key_path, key)
        FileUtils.chmod(0o600, master_key_path)

        key
      end

      private

      # Load encrypted secrets from file
      def load_secrets
        return {} unless File.exist?(@secrets_path)

        yaml_content = decrypt_file
        YAML.safe_load(yaml_content) || {}
      end

      # Decrypt the entire secrets file
      def decrypt_file
        encrypted_data = Base64.strict_decode64(File.read(@secrets_path))

        # Split: nonce (12 bytes) + ciphertext + auth_tag (16 bytes)
        nonce = encrypted_data[0...NONCE_BYTES]
        ciphertext = encrypted_data[NONCE_BYTES...-AUTH_TAG_BYTES]
        auth_tag = encrypted_data[-AUTH_TAG_BYTES..]

        # Use AES-256-GCM via OpenSSL
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = master_key
        cipher.iv = nonce
        cipher.auth_tag = auth_tag

        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError => e
        raise DecryptionError, "Failed to decrypt: #{e.message}"
      end

      # Encrypt plaintext and save to file
      def encrypt_file(plaintext)
        nonce = OpenSSL::Random.random_bytes(NONCE_BYTES)

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = master_key
        cipher.iv = nonce

        ciphertext = cipher.update(plaintext) + cipher.final
        auth_tag = cipher.auth_tag

        # Combine: nonce + ciphertext + auth_tag
        encrypted = nonce + ciphertext + auth_tag
        File.write(@secrets_path, Base64.strict_encode64(encrypted))
        FileUtils.chmod(0o600, @secrets_path)
      end

      # Decrypt a single value
      def decrypt(encrypted_value)
        return encrypted_value unless encrypted_value.is_a?(String)
        return encrypted_value unless encrypted_value.start_with?("ENC[")

        # Extract base64 from ENC[...]
        base64_data = encrypted_value[4...-1]
        encrypted_data = Base64.strict_decode64(base64_data)

        nonce = encrypted_data[0...NONCE_BYTES]
        ciphertext = encrypted_data[NONCE_BYTES...-AUTH_TAG_BYTES]
        auth_tag = encrypted_data[-AUTH_TAG_BYTES..]

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = master_key
        cipher.iv = nonce
        cipher.auth_tag = auth_tag

        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        raise DecryptionError, "Failed to decrypt secret value"
      end

      # Load master key from file
      def master_key
        @master_key ||= begin
          key_data = File.read(@master_key_path).strip
          Base64.strict_decode64(key_data)
        end
      rescue => e
        raise MasterKeyError, "Failed to load master key: #{e.message}"
      end

      # Log secret access (audit trail)
      def audit_access(name)
        entry = {
          timestamp: Time.now.iso8601,
          secret_name: name,
          pid: Process.pid
        }
        @audit_log << entry

        # Write to audit log file
        audit_path = File.join(File.dirname(@secrets_path), ".audit.log")
        File.open(audit_path, "a") do |f|
          f.puts(entry.to_json)
        end
      end

      # Flatten nested hash keys to dot notation
      def flatten_keys(hash, prefix = "")
        hash.flat_map do |key, value|
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          if value.is_a?(Hash)
            flatten_keys(value, full_key)
          else
            full_key
          end
        end
      end
    end

    # Error classes
    class SecretNotFoundError < Error; end
    class MasterKeyError < Error; end
    class DecryptionError < Error; end
  end
end
