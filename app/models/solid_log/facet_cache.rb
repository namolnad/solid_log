module SolidLog
  class FacetCache < ApplicationRecord
    self.table_name = "solid_log_facet_cache"

    validates :key_name, presence: true, uniqueness: true
    validates :cache_value, presence: true

    scope :expired, -> { where("expires_at < ?", Time.current) }
    scope :valid, -> { where("expires_at IS NULL OR expires_at >= ?", Time.current) }

    # Fetch from cache or compute and store (thread-safe with database locking)
    def self.fetch(key, ttl: 5.minutes, &block)
      # First attempt: check for existing valid cache (no lock for read-heavy workloads)
      cached = valid.find_by(key_name: key)
      return JSON.parse(cached.cache_value) if cached

      # Use database-level locking to prevent race condition
      transaction do
        # Double-check after acquiring lock (ensures only one thread computes)
        cached = valid.lock.find_by(key_name: key)
        return JSON.parse(cached.cache_value) if cached

        # No valid cache exists, compute value
        value = block.call
        store(key, value, ttl: ttl)
        value
      end
    end

    # Store a value in the cache
    def self.store(key, value, ttl: 5.minutes)
      expires_at = ttl ? Time.current + ttl : nil
      cache_value = value.to_json

      upsert(
        { key_name: key, cache_value: cache_value, expires_at: expires_at, updated_at: Time.current },
        unique_by: :key_name
      )

      value
    end

    # Invalidate a specific cache key
    def self.invalidate(key)
      find_by(key_name: key)&.destroy
    end

    # Clear all expired cache entries
    def self.cleanup_expired!
      expired.delete_all
    end

    # Clear all cache entries
    def self.clear_all!
      delete_all
    end
  end
end
