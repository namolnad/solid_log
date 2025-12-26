module SolidLog
  class RawEntry < ApplicationRecord
    self.table_name = "solid_log_raw"

    belongs_to :token, foreign_key: :token_id, optional: true
    has_one :entry, foreign_key: :raw_id, dependent: :destroy

    validates :payload, presence: true

    scope :unparsed, -> { where(parsed: false) }
    scope :parsed, -> { where(parsed: true) }
    scope :stale_unparsed, ->(threshold = 1.hour.ago) { unparsed.where("received_at < ?", threshold) }
    scope :recent, -> { order(received_at: :desc) }

    # Mark this raw entry as parsed
    def mark_parsed!
      update!(parsed: true, parsed_at: Time.current)
    end

    # Get the parsed payload as a hash
    def payload_hash
      @payload_hash ||= JSON.parse(payload)
    rescue JSON::ParserError => e
      Rails.logger.error "SolidLog: Failed to parse payload for RawEntry #{id}: #{e.message}"
      {}
    end

    # Class method to claim unparsed entries for processing
    # Returns an array of RawEntry records
    # Uses database-specific locking strategy
    def self.claim_batch(batch_size: 100)
      SolidLog.adapter.claim_batch(batch_size)
    rescue => e
      Rails.logger.error "SolidLog: Failed to claim batch: #{e.message}"
      []
    end
  end
end
