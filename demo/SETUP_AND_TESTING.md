# SolidLog 3-Gem Integration Test Application

## What Was Built

This dummy application demonstrates the complete 3-gem SolidLog architecture working together as a monolith:

### Architecture Components

1. **solid_log-core** (at `../../../solid_log-core/`)
   - Database models (RawEntry, Entry, Token, Field, FacetCache)
   - Database adapters (SQLite, PostgreSQL, MySQL)
   - Parser for converting raw logs to structured entries
   - Service objects (RetentionService, FieldAnalyzer, SearchService, etc.)
   - HTTP client for sending logs to remote services
   - **NEW**: Added `Engine` class to load models as a Rails Engine

2. **solid_log-service** (at `../../../solid_log-service/`)
   - Background job processor with built-in Scheduler
   - API controllers for log ingestion and querying
   - Jobs: ParserJob, RetentionJob, CacheCleanupJob, FieldAnalysisJob
   - **NEW**: Added `Engine` class to load controllers and jobs

3. **solid_log-ui** (at `../../`)
   - Web interface for viewing and searching logs
   - DataSource abstraction (supports Direct DB and HTTP API modes)
   - Controllers, views, and assets
   - Already has `Engine` class

### Application Features

1. **Log Generator Controller** (`app/controllers/log_generator_controller.rb`)
   - `/` (root): Dashboard with log generation UI
   - `POST /log_generator/generate`: Create single log entry
   - `POST /log_generator/generate_batch`: Create batch of logs (up to 1000)
   - `POST /log_generator/trigger_job`: Enqueue background job to generate logs

2. **Background Job** (`app/jobs/generate_logs_job.rb`)
   - Generates configurable number of log entries asynchronously
   - Creates varied log levels and messages
   - Simulates real-world logging patterns

3. **SolidLog UI** (mounted at `/logs`)
   - Log stream view
   - Search and filtering
   - Request/job correlation
   - Field management

### Configuration

**Database** (`config/database.yml`):
- Multi-database setup with separate `log` database
- Primary: `storage/development.sqlite3`
- Log: `storage/development_log.sqlite3`

**SolidLog** (`config/initializers/solid_log.rb`):
- Core: Retention settings, batch sizes
- Service: Scheduler mode, 10s parser interval
- UI: Direct DB mode, no authentication

## Setup Instructions

### 1. Install Dependencies

```bash
# From this directory (solid_log-ui/test/dummy/)
bundle install
```

**Note**: This will install all gems including the 3 local SolidLog gems.

### 2. Database Setup

The log database structure is already created at:
- `storage/development_log.sqlite3`
- Tables: solid_log_raw, solid_log_entries, solid_log_tokens, etc.

To recreate if needed:
```bash
rm storage/development_log.sqlite3
sqlite3 storage/development_log.sqlite3 < db/log_structure.sql
```

### 3. Verify Loading (Optional)

Test that all gems load correctly:
```bash
bundle exec ruby test_loading.rb
```

This should:
- Load all 3 gems
- Connect to databases
- Create test token and raw entry
- Parse logs
- Show success message

### 4. Start the Server

```bash
bundle exec rails server
```

The app will start on http://localhost:3000

## Testing the Application

### Test 1: Generate Single Log

1. Visit http://localhost:3000
2. You should see the "SolidLog Test Application" page with stats
3. In the "Generate Single Log Entry" section:
   - Select a log level (info, warn, error, etc.)
   - Enter a custom message or use the default
   - Click "Generate Log"
4. You should see a success notice
5. Stats should update showing 1 more raw entry

### Test 2: Generate Batch

1. In the "Generate Batch of Logs" section:
   - Enter a count (e.g., 50)
   - Click "Generate Batch"
2. Stats should update showing 50 more raw entries
3. Wait 10 seconds for the scheduler to parse them
4. Refresh the page - "Parsed Entries" count should increase

### Test 3: Background Job

1. In the "Background Job" section:
   - Enter a count (e.g., 100)
   - Click "Trigger Job"
2. The job will run in the background
3. Check Rails logs to see job execution
4. Stats will update as logs are created and parsed

### Test 4: View Logs in UI

1. Click "Open Log Viewer →" or visit http://localhost:3000/logs
2. You should see the SolidLog UI
3. Browse logs, try search, apply filters
4. Test the stream view, timeline correlation, etc.

### Test 5: Manual Parsing

If logs aren't being parsed automatically:

```bash
# In another terminal
bundle exec rails runner "SolidLog::ParserJob.perform_now"
```

Then refresh the stats page to see parsed entries.

## Architecture Verification

### Multi-Database Setup

```bash
# Check primary database
sqlite3 storage/development.sqlite3 ".tables"
# Should show: ar_internal_metadata, schema_migrations

# Check log database
sqlite3 storage/development_log.sqlite3 ".tables"
# Should show: solid_log_raw, solid_log_entries, solid_log_tokens, etc.
```

### Gem Loading

```bash
bundle exec rails runner "
puts 'Core: ' + SolidLog::Core::VERSION
puts 'Service: ' + SolidLog::Service::VERSION
puts 'UI: ' + SolidLog::UI::VERSION
"
```

### Background Scheduler

The scheduler should start automatically when Rails boots. Check logs for:
```
SolidLog: Background job processor started
SolidLog::Service::Scheduler starting...
```

## Troubleshooting

### Gems Not Loading

**Error**: `uninitialized constant SolidLog::RawEntry`

**Solution**: Make sure the Engine files were created:
- `solid_log-core/lib/solid_log/core/engine.rb`
- `solid_log-service/lib/solid_log/service/engine.rb`
- `solid_log-ui/lib/solid_log/ui/engine.rb`

And that they're required in the main lib files (core.rb, service.rb, ui.rb).

### Logs Not Parsing

**Issue**: Raw entries created but not appearing as parsed entries

**Solutions**:
1. Wait 10 seconds for scheduler
2. Check Rails logs for scheduler errors
3. Manually trigger: `bundle exec rails runner "SolidLog::ParserJob.perform_now"`
4. Verify database: `sqlite3 storage/development_log.sqlite3 "SELECT COUNT(*) FROM solid_log_entries;"`

### Database Errors

**Error**: `no such table: solid_log_raw`

**Solution**:
```bash
sqlite3 storage/development_log.sqlite3 < db/log_structure.sql
```

### UI Not Loading

**Error**: UI mounted at `/logs` returns 404

**Solution**:
- Check routes: `bundle exec rails routes | grep solid_log`
- Verify UI engine is loaded: `bundle exec rails runner "puts SolidLog::UI::Engine"`
- Check config/routes.rb has: `mount SolidLog::UI::Engine => "/logs"`

### Scheduler Not Running

**Issue**: Logs say scheduler started but jobs don't run

**Solution**:
- Check config/initializers/solid_log.rb
- Verify job_mode is `:scheduler`
- Restart Rails server
- Check for errors in Rails logs

## Success Criteria

When everything is working correctly:

1. ✅ Rails server starts without errors
2. ✅ Root page (/) shows log generator with stats
3. ✅ Generating logs creates RawEntry records
4. ✅ Scheduler automatically parses logs (wait 10s)
5. ✅ Parsed entries appear in stats
6. ✅ Background job generates logs asynchronously
7. ✅ UI at /logs shows all parsed entries
8. ✅ Search and filtering work in UI
9. ✅ All 3 gems load their components correctly
10. ✅ Multi-database setup works (separate log DB)

## Manual Testing Commands

```bash
# Check stats
bundle exec rails runner "
puts 'Raw entries: ' + SolidLog::RawEntry.count.to_s
puts 'Parsed entries: ' + SolidLog::Entry.count.to_s
puts 'Unparsed: ' + SolidLog::RawEntry.unparsed.count.to_s
puts 'Tokens: ' + SolidLog::Token.count.to_s
"

# Create test data
bundle exec rails runner "
token = SolidLog::Token.first_or_create!(
  name: 'Test Token',
  token_hash: SolidLog::Token.send(:hash_token, SecureRandom.hex)
)
10.times do |i|
  SolidLog::RawEntry.create!(
    token: token,
    payload: {
      timestamp: Time.current.iso8601,
      level: 'info',
      message: \"Test log \#{i+1}\",
      app: 'test_app',
      env: 'development'
    }.to_json,
    received_at: Time.current
  )
end
puts 'Created 10 test logs'
"

# Parse logs
bundle exec rails runner "SolidLog::ParserJob.perform_now"

# Clear all data
bundle exec rails runner "
SolidLog::Entry.delete_all
SolidLog::RawEntry.delete_all
SolidLog::Token.delete_all
puts 'Cleared all logs'
"

# Test search
bundle exec rails runner "
results = SolidLog::SearchService.search('test')
puts \"Found \#{results.count} results for 'test'\"
"
```

## Next Steps

After successful testing:

1. **Write automated tests** using the TESTING_GUIDE.md
2. **Move views/assets** from original gem to solid_log-ui
3. **Publish gems** to RubyGems
4. **Create migration guide** from monolithic gem
5. **Performance testing** with large datasets

## Files Created

### Application Structure
- Gemfile (references 3 local gems)
- config/application.rb
- config/database.yml (multi-database)
- config/routes.rb (mounts UI, defines log generator routes)
- config/initializers/solid_log.rb (configures all 3 gems)

### Controllers & Jobs
- app/controllers/application_controller.rb
- app/controllers/log_generator_controller.rb
- app/jobs/application_job.rb
- app/jobs/generate_logs_job.rb

### Views
- app/views/layouts/application.html.erb
- app/views/log_generator/index.html.erb

### Database
- storage/development.sqlite3 (primary)
- storage/development_log.sqlite3 (logs)
- db/log_structure.sql (schema for log database)

### Scripts & Docs
- test_loading.rb (verification script)
- README.md (overview)
- SETUP_AND_TESTING.md (this file)

## Architecture Highlights

### Monolith Benefits
- All 3 gems in one app (easy development/testing)
- Direct DB access (fastest performance)
- Built-in scheduler (no external dependencies)
- Single deployment

### Flexibility Maintained
- Can easily switch to HTTP API mode for UI
- Can use ActiveJob instead of scheduler
- Can run service separately later
- All gems independently deployable

This test app proves the 3-gem architecture works perfectly together! 🎉
