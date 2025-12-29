require "openssl"
require "active_support/security_utils"

module SolidLog
  class Token < Record
    self.table_name = "solid_log_tokens"

    has_many :raw_entries, foreign_key: :token_id, dependent: :nullify

    validates :name, presence: true
    validates :token_hash, presence: true, uniqueness: true

    # Generate a new token and return it (only time it's visible)
    def self.generate!(name)
      plaintext = "slk_" + SecureRandom.hex(32)
      token = new(name: name)
      token.token_hash = hash_token(plaintext)
      token.save!

      {
        id: token.id,
        name: token.name,
        token: plaintext,
        created_at: token.created_at
      }
    end

    # Authenticate a plaintext token - O(1) database lookup
    def self.authenticate(plaintext)
      return nil if plaintext.blank?

      hashed = hash_token(plaintext)
      find_by(token_hash: hashed)
    end

    # Authenticate a plaintext token against this token's hash
    def authenticate(plaintext)
      return false if plaintext.blank? || token_hash.blank?

      # Use constant-time comparison to prevent timing attacks
      ActiveSupport::SecurityUtils.secure_compare(
        self.class.hash_token(plaintext),
        token_hash
      )
    end

    # Touch last_used_at timestamp
    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    private

    # Generate deterministic hash using HMAC-SHA256
    # This allows O(1) database lookups while maintaining security
    def self.hash_token(plaintext)
      secret_key = Rails.application.secret_key_base || raise("secret_key_base not configured")
      OpenSSL::HMAC.hexdigest("SHA256", secret_key, plaintext)
    end
  end
end
