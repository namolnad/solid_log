# Testing SolidLog Puma Plugin in Demo App

The demo app is now configured to support **two modes**:

1. **Puma Plugin mode** (NEW) - Inline processing via background thread
2. **Service mode** (existing) - Separate scheduler process

## Architecture: DirectLogger + Puma Plugin

In Puma Plugin mode, logs flow directly to the database without any HTTP:

```
Rails app → DirectLogger → RawEntry table → Puma plugin → Entry table
```

**No HTTP, no tokens, no secret key needed!** The secret is only for HTTP API authentication when using solid_log-service.

## Test the Puma Plugin (NEW)

### 0. Install Dependencies

```bash
cd /Users/danloman/Developer/solid_log/demo

# Install lograge (needed for DirectLogger)
bundle install
```

### 1. Start Puma with Plugin

```bash
# Enable the plugin via env var
SOLIDLOG_PUMA_PLUGIN_ENABLED=true bin/rails server
```

**Expected output:**
```
Starting SolidLog inline parsing (Puma plugin mode)
  Parse interval: 5s
  Batch size: 100
```

You should **NOT** see "Background job processor started (Service mode)"

### 2. Generate Test Logs

Since DirectLogger is configured, you have multiple ways to generate logs:

**Option A: Use the Log Generator UI**
```
http://localhost:3000/log_generator
```
- Click "Generate Log" to create single logs via Rails.logger
- Click "Generate Batch" to create raw entries directly (for testing throughput)
- All logs flow through the Puma plugin (no HTTP, no tokens)

**Option B: Navigate pages (automatic logging)**

Every Rails request is automatically logged:
```
http://localhost:3000/
http://localhost:3000/solidlog
```

**Option C: Curl requests**
```bash
curl http://localhost:3000/
curl http://localhost:3000/solidlog
```

Within 5 seconds, check the Puma logs - you should see the parser processing:
```
SolidLog Puma Plugin: Processed N, inserted N, errors 0
```

### 3. Generate Test Logs (via rails runner)

Alternatively, create raw entries manually for testing:

In another terminal:

```bash
cd /Users/danloman/Developer/solid_log/demo

# Create 20 test log entries
bin/rails runner "
  puts 'Creating 20 test log entries...'
  20.times do |i|
    SolidLog::RawEntry.create!(
      payload: {
        timestamp: Time.current.iso8601,
        level: %w[info warn error].sample,
        message: \"Test log #{i}\",
        app: 'demo-app',
        user_id: rand(1..100),
        request_id: SecureRandom.uuid
      }.to_json,
      received_at: Time.current
    )
  end
  puts 'Created 20 raw entries!'
  puts 'Check the Puma server logs in 5-10 seconds...'
"
```

### 3. Watch the Magic Happen

Within 5-10 seconds, you should see in the Puma server logs:

```
SolidLog::BatchParsingService: Processing 20 raw entries
SolidLog::BatchParsingService: Inserted 20 entries
SolidLog Puma Plugin: Processed 20, inserted 20, errors 0
```

### 4. Verify Parsing

Wait 5-10 seconds after generating logs, then check:

```bash
bin/rails runner "
  puts \"Raw entries: #{SolidLog::RawEntry.count}\"
  puts \"Parsed entries: #{SolidLog::Entry.count}\"
  puts \"Unparsed: #{SolidLog::RawEntry.unparsed.count}\"
  puts \"Fields tracked: #{SolidLog::Field.count}\"
  puts \"\"
  puts 'Field usage:'
  SolidLog::Field.all.each do |f|
    puts \"  #{f.name}: #{f.usage_count} times (#{f.field_type})\"
  end
"
```

**Expected output:**
```
Raw entries: 20
Parsed entries: 20
Unparsed: 0
Fields tracked: 2
Field usage:
  user_id: 20 times (number)
  request_id: 20 times (string)
```

### 5. Test Live Tail with ActionCable

1. Keep the server running with the plugin
2. Open browser: http://localhost:3000/solidlog
3. Click the "Live Tail" button
4. In another terminal, generate logs continuously:

```bash
bin/rails runner "
  puts 'Generating live logs (Ctrl+C to stop)...'
  loop do
    SolidLog::RawEntry.create!(
      payload: {
        timestamp: Time.current.iso8601,
        level: 'info',
        message: \"Live test at #{Time.current.strftime('%H:%M:%S')}\"
      }.to_json,
      received_at: Time.current
    )
    sleep 3
  end
"
```

Watch the logs appear in real-time in the UI!

## Compare with Service Mode (Existing)

### Start Server in Service Mode

```bash
# Do NOT set SOLIDLOG_PUMA_PLUGIN_ENABLED
bin/rails server
```

**Expected output:**
```
SolidLog: Background job processor started (Service mode)
```

You should **NOT** see "Starting SolidLog inline parsing"

The Service mode will parse entries every 10 seconds using the scheduler.

## Performance Test

Test throughput with larger batches:

```bash
bin/rails runner "
  puts 'Creating 500 raw entries...'
  batch = []
  500.times do |i|
    batch << {
      payload: {
        timestamp: Time.current.iso8601,
        level: 'info',
        message: \"Perf test #{i}\",
        user_id: i
      }.to_json,
      received_at: Time.current
    }
  end
  SolidLog::RawEntry.insert_all(batch)
  puts 'Created 500 entries'
  puts 'Waiting for Puma plugin to process (watch server logs)...'
"
```

Watch the Puma server logs - you should see multiple batches being processed:
```
SolidLog Puma Plugin: Processed 100, inserted 100, errors 0
SolidLog Puma Plugin: Processed 100, inserted 100, errors 0
... (5 batches total)
```

## Cleanup

```bash
bin/rails runner "
  SolidLog::Entry.delete_all
  SolidLog::RawEntry.delete_all
  SolidLog::Field.delete_all
  puts 'Cleaned up all test data'
"
```

## Troubleshooting

### Plugin Not Starting

Check:
1. `SOLIDLOG_PUMA_PLUGIN_ENABLED=true` is set when starting server
2. Puma logs show "Starting SolidLog inline parsing"
3. Config shows `inline_parsing_enabled = true`

### Entries Not Being Parsed

1. Check unparsed count: `SolidLog::RawEntry.unparsed.count`
2. Wait at least 5 seconds (parse_interval)
3. Check Puma logs for errors

### Both Plugin and Service Running

Make sure only ONE is active:
- **Plugin mode:** Set `SOLIDLOG_PUMA_PLUGIN_ENABLED=true`
- **Service mode:** Don't set the env var

They won't conflict (both use `claim_batch` with locking), but it's inefficient.

## Configuration

Current settings (in `config/initializers/solid_log.rb`):

- **parse_interval:** 5 seconds (how often to poll)
- **parser_batch_size:** 100 entries per cycle
- **Throughput:** ~1,200 entries/minute (20 entries × 12 cycles/min)

To increase throughput, adjust in the initializer:
```ruby
config.parse_interval = 10  # Less frequent
config.parser_batch_size = 1000  # Larger batches
```

## Success Criteria

✅ Server starts with "Starting SolidLog inline parsing"
✅ Service scheduler does NOT start
✅ Raw entries get parsed within 5-10 seconds
✅ Unparsed count drops to 0
✅ Live tail shows entries in real-time
✅ No errors in server logs
