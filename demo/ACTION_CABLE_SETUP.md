# Action Cable Setup for Live Tail

## Configuration Complete ✅

I've set up Solid Cable with a memory store in the test/dummy app for testing the live tail feature.

### What's Been Configured:

1. **Gemfile** - Added `solid_cable` gem
2. **config/cable.yml** - Configured memory adapter for development and test
3. **config/routes.rb** - Mounted Action Cable at `/cable`
4. **config/initializers/action_cable.rb** - Configured cable URL and CORS settings

### Configuration Details:

**Cable Adapter (config/cable.yml):**
```yaml
development:
  adapter: memory

test:
  adapter: memory
```

**Cable Route:**
```ruby
mount ActionCable.server => "/cable"
```

**WebSocket URL:**
- Local: `ws://localhost:3000/cable`

### Live Tail Channel

The `LogStreamChannel` is already implemented in the UI gem at:
`solid_log-ui/app/channels/solid_log/ui/log_stream_channel.rb`

**Features:**
- Filter-based streaming (users only see logs matching their filters)
- Automatic filter registration and expiry (5 minutes)
- Heartbeat support to keep subscriptions active

### Testing Live Tail

1. **Start the dummy app:**
   ```bash
   cd solid_log-ui/test/dummy
   bundle install  # If not already done
   bin/rails server
   ```

2. **Visit the UI:**
   - Navigate to http://localhost:3000/logs
   - Go to the Streams page
   - Enable "Live Tail" mode

3. **Generate logs:**
   - Open another tab to http://localhost:3000
   - Use the log generator to create new log entries
   - Watch them appear in real-time on the Streams page

4. **Test filters:**
   - Apply filters (level, app, env, etc.)
   - Only matching logs should appear in live tail
   - Different filter combinations use different streams

### How It Works:

1. **Client subscribes** to LogStreamChannel with filters
2. **Channel generates** a unique stream name based on filter hash
3. **Filters are cached** in Rails.cache (memory store) with 5min expiry
4. **New entries** trigger broadcasts to matching streams
5. **Frontend receives** real-time updates via WebSocket

### Broadcasting New Entries:

When new log entries are created/parsed, broadcast them:

```ruby
# In ParserJob or entry creation
def broadcast_entry(entry)
  # Get all active filter combinations
  SolidLog::UI::LogStreamChannel.active_filter_combinations.each do |filter_key, filters|
    if entry_matches_filters?(entry, filters)
      stream_name = "solid_log_stream_#{filter_key}"
      ActionCable.server.broadcast(stream_name, {
        entry: entry.as_json(methods: [:extra_fields_hash])
      })
    end
  end
end
```

### Memory Store Benefits:

- **No database setup** required for cable
- **Fast** - All in-memory
- **Perfect for development** and testing
- **Auto-cleanup** on app restart

### Production Note:

For production, switch to Solid Cable with database persistence in `config/cable.yml`:

```yaml
production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
```

This provides persistence across server restarts and supports multiple app instances.
