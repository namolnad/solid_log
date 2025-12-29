module SolidLog
  module UI
    class LogStreamChannel < ApplicationCable::Channel
    CACHE_NAMESPACE = "solid_log:active_filters"
    CACHE_EXPIRY = 5.minutes

    def subscribed
      # Store the filters for this subscription
      @filters = params[:filters] || {}
      @filter_key = generate_filter_key(@filters)

      # Subscribe to new entries broadcast from service
      # Service broadcasts entry IDs, we filter and render them
      stream_from "solid_log_new_entries", coder: ActiveSupport::JSON do |data|
        handle_new_entries(data["entry_ids"]) if data["entry_ids"]
      end

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

    def handle_new_entries(entry_ids)
      return if entry_ids.blank?

      Rails.logger.info "[LogStreamChannel] Received broadcast with #{entry_ids.size} entry IDs: #{entry_ids.first(5)}"

      # Fetch entries matching these IDs
      entries = SolidLog::Entry.where(id: entry_ids).order(:id)
      Rails.logger.info "[LogStreamChannel] Found #{entries.size} entries in database"

      # Filter to only entries matching this client's filters
      transmitted_count = 0
      entries.each do |entry|
        matches = entry_matches_filters?(entry)
        Rails.logger.debug "[LogStreamChannel] Entry #{entry.id} matches filters: #{matches}"
        next unless matches

        # Render HTML for this specific entry with proper route context
        html = SolidLog::UI::BaseController.render(
          partial: "solid_log/ui/streams/log_row",
          locals: { entry: entry, query: nil },
          layout: false
        )

        # Transmit to this specific client
        transmit({ html: html, entry_id: entry.id })
        transmitted_count += 1
      end

      Rails.logger.info "[LogStreamChannel] Transmitted #{transmitted_count} entries to client (filter: #{@filter_key})"
    end

    def entry_matches_filters?(entry)
      return true if @filters.blank?

      # Check each filter condition
      @filters.each do |key, values|
        values = Array(values).reject(&:blank?)
        next if values.empty?

        entry_value = entry.public_send(key) rescue nil
        return false if entry_value.nil?

        unless values.map(&:to_s).include?(entry_value.to_s)
          return false
        end
      end

      true
    end
    end
  end
end
