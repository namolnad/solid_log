# Recursive Logging Prevention

SolidLog includes built-in protection against recursive logging to prevent infinite loops where the logging system logs its own operations.

## How It Works

SolidLog uses a thread-local flag (`Thread.current[:solid_log_silenced]`) to track when it's performing internal operations. Any logger, log subscriber, or custom logging code can check this flag to prevent recursive logging.

### Architecture

```
User Request → SolidLog API
    ↓
Middleware sets flag: Thread.current[:solid_log_silenced] = true
    ↓
API Controller → RawEntry.create! (wrapped in SolidLog.without_logging)
    ↓
Your Logger checks flag → sees it's true → skips logging
    ↓
No infinite recursion!
```

## Automatic Protection

### 1. HTTP API Requests

The `SilenceMiddleware` automatically silences all requests to SolidLog routes:

```ruby
# Automatically silenced:
# - /solid_log/*
# - /admin/logs/*
# - /api/v1/ingest
```

### 2. Internal Operations

All SolidLog internal operations use `SolidLog.without_logging`:

```ruby
SolidLog.without_logging do
  RawEntry.create!(raw_payload: payload)
  Entry.create!(parsed_data)
  Field.track("user_id", 42)
end
```

## Custom Logger Integration

If you're implementing a custom logger or log subscriber, check the silence flag:

### Option 1: ActiveSupport::Notifications Subscriber

```ruby
ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  # Skip if SolidLog is performing internal operations
  next if Thread.current[:solid_log_silenced]
  
  event = ActiveSupport::Notifications::Event.new(*args)
  # ... send to SolidLog HTTP API
end
```

### Option 2: Custom LogDevice

```ruby
class MySolidLogDevice
  def write(message)
    # Skip if SolidLog is performing internal operations
    return if Thread.current[:solid_log_silenced]
    
    # Parse and send to SolidLog
    send_to_solidlog(message)
  end
end
```

### Option 3: Use Built-in LogSubscriber

SolidLog provides an optional `LogSubscriber` that respects the silence flag:

```ruby
# config/initializers/solid_log.rb
require "solid_log/log_subscriber"

SolidLog.configure do |config|
  config.client_token = ENV["SOLIDLOG_TOKEN"]
  config.ingestion_url = "http://localhost:3000/solid_log/api/v1/ingest"
end

# Attach to Rails logger
Rails.logger.extend(ActiveSupport::TaggedLogging)
Rails.logger.broadcast_to(SolidLog::LogSubscriber.logger)

# Start background flush thread
SolidLog::LogSubscriber.start_flush_thread(interval: 5, batch_size: 100)

# Graceful shutdown
at_exit { SolidLog::LogSubscriber.stop_flush_thread }
```

## Testing

Verify your logger respects the silence flag:

```ruby
test "my_logger respects solid_log_silenced flag" do
  logged_messages = []
  
  # Normal logging should work
  my_logger.info("Normal message")
  assert_equal 1, logged_messages.size
  
  # Logging inside without_logging should be silenced
  SolidLog.without_logging do
    my_logger.info("Should be silenced")
  end
  assert_equal 1, logged_messages.size, "Should not log during SolidLog operations"
end
```

## Comparison to Logster

SolidLog's approach is inspired by [discourse/logster](https://github.com/discourse/logster) but simpler:

**Logster:**
- Uses `Thread.current[Logster::Logger::LOGSTER_ENV]` to detect nested logging
- Has `@skip_store` flag for chained loggers
- More complex multi-layered protection

**SolidLog:**
- Uses single `Thread.current[:solid_log_silenced]` flag
- Simpler implementation
- Relies on HTTP-based architecture (no file I/O)

## Common Pitfalls

### ❌ Don't: Log from within SolidLog operations

```ruby
# BAD - Will create infinite loop
class MyBrokenLogger
  def write(message)
    # This will recursively call itself!
    RawEntry.create!(raw_payload: message)
  end
end
```

### ✅ Do: Check the silence flag

```ruby
# GOOD - Prevents recursion
class MySafeLogger
  def write(message)
    return if Thread.current[:solid_log_silenced]
    
    # Safe to call SolidLog HTTP API
    send_to_solidlog(message)
  end
end
```

## Thread Safety

The silence flag is thread-local, so concurrent requests are isolated:

```ruby
# Thread 1: SolidLog request
Thread.current[:solid_log_silenced] = true

# Thread 2: Normal user request  
Thread.current[:solid_log_silenced] # => nil
```

This ensures that silencing in one thread doesn't affect logging in other threads.

## Manual Control

You can manually wrap any code that should not trigger logging:

```ruby
SolidLog.without_logging do
  # Any database operations here won't be logged
  User.create!(name: "Test")
  Post.where(published: true).update_all(featured: false)
end
```

The flag is automatically cleared when the block exits, even if an exception occurs.
