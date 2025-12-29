# SolidLog Test Application

This is a test/dummy application that demonstrates all 3 SolidLog gems working together in a monolith configuration.

## Architecture

This app uses:
- **solid_log-core**: Database models, adapters, parser, services (local gem)
- **solid_log-service**: Background job processing with built-in Scheduler (local gem)
- **solid_log-ui**: Web interface for viewing logs (local gem)

## Setup

```bash
# 1. Install dependencies
bundle install

# 2. Create databases
mkdir -p storage
touch storage/development.sqlite3
touch storage/development_log.sqlite3

# 3. Load log database structure
sqlite3 storage/development_log.sqlite3 < db/log_structure.sql

# 4. Start the server
bin/rails server
```

## Usage

### Generate Logs

Visit http://localhost:3000

The root path shows a log generator interface where you can:
- Generate single log entries at different levels (debug, info, warn, error, fatal)
- Generate batches of random log entries
- Trigger a background job that generates logs

### View Logs

Visit http://localhost:3000/logs

The SolidLog UI is mounted at `/logs` and provides:
- Log stream view
- Search and filtering
- Request/job correlation
- Field management

## How It Works

1. **Log Generation**: The LogGeneratorController creates `SolidLog::RawEntry` records
2. **Background Processing**: The Scheduler (from solid_log-service) runs `ParserJob` every 10 seconds
3. **Parsing**: Parser converts raw entries into structured `SolidLog::Entry` records
4. **Viewing**: The UI (solid_log-ui) queries entries using Direct DB mode

## Configuration

See `config/initializers/solid_log.rb` for the full configuration:

- **Core**: Retention settings, batch sizes, field promotion
- **Service**: Scheduler intervals (parser every 10s, cleanup hourly, retention at 2 AM)
- **UI**: Direct DB mode, no authentication, compact view style

## Testing End-to-End

1. Visit http://localhost:3000
2. Click "Generate Batch" with count=100
3. Wait 10 seconds for scheduler to parse
4. Visit http://localhost:3000/logs to see parsed entries
5. Try searching, filtering, and exploring the UI

## Manual Commands

```bash
# Parse logs immediately (instead of waiting for scheduler)
bin/rails runner "SolidLog::ParserJob.perform_now"

# Check database stats
bin/rails runner "puts \"Raw: #{SolidLog::RawEntry.count}, Parsed: #{SolidLog::Entry.count}\""

# Clear all logs
bin/rails runner "SolidLog::RawEntry.delete_all; SolidLog::Entry.delete_all"

# Create a test token
bin/rails runner "SolidLog::Token.create!(name: 'Test', token_hash: SolidLog::Token.send(:hash_token, 'test123'))"
```

## Architecture Highlights

### Monolith Configuration
All 3 gems are loaded in the same application, configured to work together:

- Core provides the data models and services
- Service runs the background scheduler in the same process
- UI uses Direct DB mode for fast access

### Multi-Database Setup
The app uses Rails' multi-database features:
- `primary`: Main application database (development.sqlite3)
- `log`: Separate log database (development_log.sqlite3)

All SolidLog models connect to the `log` database automatically.

### Background Job Processing
Uses the built-in Scheduler from solid_log-service:
- Runs in a separate thread
- No external dependencies (no Redis, no Sidekiq)
- Configurable intervals for each job type

## Troubleshooting

### Logs not appearing in UI
- Wait 10 seconds for the scheduler to parse raw entries
- Or run manually: `bin/rails runner "SolidLog::ParserJob.perform_now"`
- Check raw entries: `bin/rails runner "puts SolidLog::RawEntry.unparsed.count"`

### Scheduler not running
- Check Rails logs for "SolidLog: Background job processor started"
- Verify config in `config/initializers/solid_log.rb`
- Restart the server to restart the scheduler

### Database errors
- Ensure structure.sql was loaded: `sqlite3 storage/development_log.sqlite3 ".tables"`
- Should see: solid_log_entries, solid_log_raw, solid_log_tokens, etc.

## License

MIT
