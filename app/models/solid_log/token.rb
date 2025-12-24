require "bcrypt"

module SolidLog
  class Token < ApplicationRecord
    self.table_name = "solid_log_tokens"

    has_many :raw_entries, foreign_key: :token_id, dependent: :nullify

    validates :name, presence: true
    validates :token_hash, presence: true, uniqueness: true

    attr_accessor :plaintext_token

    before_create :hash_token

    # Generate a new token and return it (only time it's visible)
    def self.generate!(name)
      plaintext = "slk_" + SecureRandom.hex(32)
      token = new(name: name)
      token.token_hash = BCrypt::Password.create(plaintext)
      token.save!

      {
        id: token.id,
        name: token.name,
        token: plaintext,
        created_at: token.created_at
      }
    end

    # Authenticate a plaintext token
    def self.authenticate(plaintext)
      return nil if plaintext.blank?

      token_hash = BCrypt::Password.new(BCrypt::Password.create(plaintext)).to_s

      # Find all tokens and check each one (constant-time comparison)
      all.find do |token|
        BCrypt::Password.new(token.token_hash) == plaintext
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end

    # Authenticate a plaintext token against this token's hash
    def authenticate(plaintext)
      return false if plaintext.blank? || token_hash.blank?

      BCrypt::Password.new(token_hash) == plaintext
    rescue BCrypt::Errors::InvalidHash
      false
    end

    # Touch last_used_at timestamp
    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    private

    def hash_token
      if plaintext_token.present?
        self.token_hash = BCrypt::Password.create(plaintext_token)
      end
    end
  end
end
