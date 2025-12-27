module SolidLog
  class LogStreamChannel < ApplicationCable::Channel
    CACHE_NAMESPACE = "solid_log:active_filters"
    CACHE_EXPIRY = 5.minutes

    def subscribed
      # Create a unique stream name based on the user's filters
      # This ensures users only receive entries matching their filters
      filter_key = generate_filter_key(params[:filters] || {})
      stream_name = "solid_log_stream_#{filter_key}"

      stream_from stream_name

      # Store the filters for this subscription
      @filters = params[:filters] || {}
      @stream_name = stream_name
      @filter_key = filter_key

      # Register this filter combination in Rails.cache
      # Expires after 5 minutes of inactivity (refreshed on heartbeat)
      cache_key = "#{CACHE_NAMESPACE}:#{@filter_key}"
      Rails.cache.write(cache_key, @filters, expires_in: CACHE_EXPIRY)

      # Also add to the set of active filter keys
      register_active_filter_key(@filter_key)
    end

    def unsubscribed
      # Cleanup when channel is unsubscribed
      stop_all_streams

      # Cache entries will expire naturally after CACHE_EXPIRY
      # This handles the case where multiple clients use same filters
    end

    def refresh_subscription
      # Called periodically by client to keep subscription active in cache
      # This prevents the filter from expiring while user is actively watching
      if @filter_key
        cache_key = "#{CACHE_NAMESPACE}:#{@filter_key}"
        Rails.cache.write(cache_key, @filters, expires_in: CACHE_EXPIRY)
        register_active_filter_key(@filter_key)
      end
    end

    def self.active_filter_combinations
      # Read all active filter combinations from cache
      active_keys = Rails.cache.read("#{CACHE_NAMESPACE}:keys") || []

      filters_hash = {}
      active_keys.each do |key|
        cache_key = "#{CACHE_NAMESPACE}:#{key}"
        filters = Rails.cache.read(cache_key)
        filters_hash[key] = filters if filters
      end

      filters_hash
    end

    private

    def generate_filter_key(filters)
      # Create a consistent hash based on filter values
      # Sort to ensure same filters = same key regardless of order
      normalized = filters.sort.to_h
      Digest::MD5.hexdigest(normalized.to_json)
    end

    def register_active_filter_key(filter_key)
      # Maintain a list of active filter keys in cache
      keys_cache_key = "#{CACHE_NAMESPACE}:keys"

      # Read current keys, add this one, write back
      # Note: This has a race condition but it's acceptable for this use case
      current_keys = Rails.cache.read(keys_cache_key) || []
      current_keys << filter_key unless current_keys.include?(filter_key)

      # Keep the list alive as long as any filter is active
      Rails.cache.write(keys_cache_key, current_keys.uniq, expires_in: CACHE_EXPIRY)
    end
  end
end
