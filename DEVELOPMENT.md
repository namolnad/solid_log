# SolidLog Development Guide

Guide for developers working on SolidLog itself.

## Setup

### 1. Clone and Install

```bash
git clone https://github.com/yourusername/solid_log.git
cd solid_log
bundle install
```

### 2. Set Up Test Database

```bash
cd test/dummy
rails db:create
rails db:migrate

# Or use the in-memory SQLite test setup (automatic during test runs)
```

## Running Tests

### Quick Test Suite

```bash
# Run all tests
bundle exec rake test

# Run with verbose output
bundle exec rake test TESTOPTS="-v"
```

### Individual Test Files

```bash
# Model tests
bundle exec ruby -Itest test/models/solid_log/token_test.rb
bundle exec ruby -Itest test/models/solid_log/entry_test.rb
bundle exec ruby -Itest test/models/solid_log/raw_entry_test.rb
bundle exec ruby -Itest test/models/solid_log/field_test.rb
bundle exec ruby -Itest test/models/solid_log/facet_cache_test.rb

# Service tests
bundle exec ruby -Itest test/services/solid_log/parser_test.rb

# Controller tests
bundle exec ruby -Itest test/controllers/solid_log/api/v1/ingest_controller_test.rb

# Integration tests
bundle exec ruby -Itest test/integration/solid_log/ingestion_flow_test.rb
bundle exec ruby -Itest test/integration/solid_log/silence_logging_test.rb
```

### Test Summary

Run the comprehensive test summary script:

```bash
bash /tmp/test_summary_full.sh
```

Example output:
```
=== FULL TEST SUMMARY ===

token_test: 8 runs, 21 assertions, 0 failures, 0 errors, 0 skips
entry_test: 24 runs, 84 assertions, 0 failures, 0 errors, 0 skips
raw_entry_test: 13 runs, 27 assertions, 0 failures, 0 errors, 0 skips
parser_test: 11 runs, 34 assertions, 0 failures, 0 errors, 0 skips
field_test: 13 runs, 21 assertions, 0 failures, 0 errors, 0 skips
facet_cache_test: 8 runs, 11 assertions, 0 failures, 0 errors, 0 skips
ingest_controller_test: 8 runs, 18 assertions, 0 failures, 0 errors, 0 skips
ingestion_flow_test: 7 runs, 34 assertions, 0 failures, 0 errors, 0 skips
silence_logging_test: 6 runs, 12 assertions, 0 failures, 0 errors, 0 skips

TOTAL: 98 tests, 262 assertions
```

## Test Architecture

### In-Memory Database

Tests use SQLite in-memory database for speed:

```ruby
# test/test_helper.rb
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
load File.expand_path("dummy/db/log_schema.rb", __dir__)
```

Key features:
- Fast test execution (no disk I/O)
- Clean slate for each test run
- FTS5 triggers created automatically

### Test Helpers

Located in `test/test_helper.rb`:

```ruby
# Create a test token
token = create_test_token(name: "Test Token")
# Returns: {id: 1, name: "Test Token", token: "slk_...", model: <Token>}

# Create a raw entry
raw_entry = create_raw_entry(payload: {message: "test"}, token: token)

# Create a parsed entry
entry = create_entry(level: "info", message: "test")

# Create multiple entries
entries = create_entries(10, level: "error")
```

### Test Categories

**Unit Tests (Models/Services)**
- Fast, isolated
- Test single methods
- Use mocks/stubs sparingly

**Integration Tests**
- Test full workflows
- HTTP → ingestion → parsing → querying
- Database interactions

**Concurrency Tests**
- Thread-safety verification
- Race condition detection
- Use `Concurrent::AtomicFixnum` and `Concurrent::Set`

## Code Structure

```
solid_log/
├── app/
│   ├── controllers/      # API and UI controllers
│   ├── models/           # ActiveRecord models
│   ├── jobs/             # Background jobs
│   ├── services/         # Business logic (optional)
│   └── views/            # UI templates
├── lib/
│   └── solid_log/
│       ├── adapters/     # Database-specific implementations
│       ├── configuration.rb
│       ├── parser.rb     # JSON log parser
│       ├── silence_middleware.rb
│       └── log_subscriber.rb  # Optional Rails integration
├── test/
│   ├── dummy/            # Test Rails app
│   ├── models/
│   ├── services/
│   ├── controllers/
│   └── integration/
└── docs/                 # Documentation
```

## Writing Tests

### Testing Thread Safety

```ruby
test "method is thread-safe" do
  counter = Concurrent::AtomicFixnum.new(0)
  
  threads = 10.times.map do
    Thread.new do
      YourClass.expensive_operation do
        counter.increment
      end
    end
  end
  
  threads.each(&:join)
  
  # Verify operation executed exactly once
  assert_equal 1, counter.value
end
```

### Testing Database Locking

```ruby
test "claim_batch prevents duplicate claims" do
  20.times { create_raw_entry }
  
  claimed_ids = Concurrent::Set.new
  threads = 5.times.map do
    Thread.new do
      batch = RawEntry.claim_batch(batch_size: 5)
      batch.each { |entry| claimed_ids.add(entry.id) }
    end
  end
  
  threads.each(&:join)
  
  assert_equal 20, claimed_ids.size, "No duplicates should be claimed"
end
```

### Testing Silence Mechanism

```ruby
test "without_logging prevents recursive logging" do
  logged_queries = []
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    logged_queries << args unless Thread.current[:solid_log_silenced]
  end
  
  SolidLog.without_logging do
    RawEntry.create!(raw_payload: "{}", token_id: 1, received_at: Time.current)
  end
  
  assert_equal 0, logged_queries.size, "Should not log during silenced operations"
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber)
end
```

## Debugging Tests

### Enable Verbose SQL

```ruby
# In a specific test
ActiveRecord::Base.logger = Logger.new(STDOUT)
```

### Inspect Database State

```ruby
test "my test" do
  # ... test code
  
  # Debug database state
  puts "Raw entries: #{RawEntry.count}"
  puts "Unparsed: #{RawEntry.unparsed.count}"
  puts "Entries: #{Entry.count}"
  
  # Inspect specific record
  pp RawEntry.last
end
```

### Rails Console in Dummy App

```bash
cd test/dummy
rails console

# Manually test operations
token = SolidLog::Token.generate!("Test")
raw = SolidLog::RawEntry.create!(
  raw_payload: {message: "test"}.to_json,
  token_id: token[:id],
  received_at: Time.current
)
SolidLog::ParserJob.perform_now
SolidLog::Entry.last
```

## Database Adapters

### Testing Different Adapters

The test suite uses SQLite by default. To test PostgreSQL or MySQL:

```bash
# Set environment variable
export SOLIDLOG_TEST_ADAPTER=postgresql

# Or create a custom test helper
```

### Adding New Adapter Support

1. Create adapter class in `lib/solid_log/adapters/`
2. Inherit from `BaseAdapter`
3. Implement required methods:
   - `fts_search(query)`
   - `claim_batch(batch_size)`
   - `extract_json_field(column, field_name)`
   - `supports_full_text_search?`
   - `supports_skip_locked?`
4. Add to `AdapterFactory.build_adapter`
5. Write tests in `test/lib/adapters/`

## Performance Testing

### Bulk Ingestion

```ruby
# test/performance/ingestion_test.rb
test "can ingest 1000 logs in under 1 second" do
  token = create_test_token
  
  logs = 1000.times.map do |i|
    {
      raw_payload: {message: "Log #{i}"}.to_json,
      token_id: token[:id],
      received_at: Time.current
    }
  end
  
  time = Benchmark.realtime do
    RawEntry.insert_all(logs)
  end
  
  assert time < 1.0, "Bulk insert took #{time}s (should be < 1s)"
end
```

### Parser Performance

```ruby
test "parser processes 100 entries in under 2 seconds" do
  100.times { create_raw_entry }
  
  time = Benchmark.realtime do
    while RawEntry.unparsed.any?
      ParserJob.perform_now
    end
  end
  
  assert time < 2.0, "Parsing took #{time}s (should be < 2s)"
end
```

## Linting and Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix simple issues
bundle exec rubocop -a

# Check specific file
bundle exec rubocop app/models/solid_log/entry.rb
```

## Documentation

Update documentation when adding features:

```
docs/
├── API.md                          # HTTP API reference
├── ARCHITECTURE.md                 # System design
├── DATABASE_ADAPTERS.md            # Adapter guide
├── DEPLOYMENT.md                   # Production deployment
└── RECURSIVE_LOGGING_PREVENTION.md # Silence mechanism
```

## Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "Add feature X"

# Run tests before pushing
bundle exec rake test

# Push to remote
git push origin feature/my-feature

# Create pull request
```

## Common Development Tasks

### Adding a New Model

```bash
# Generate migration
rails generate migration CreateSolidLogThings name:string

# Write model
# app/models/solid_log/thing.rb

# Write tests
# test/models/solid_log/thing_test.rb

# Run tests
bundle exec ruby -Itest test/models/solid_log/thing_test.rb
```

### Adding a New Controller Action

```ruby
# Add route in config/routes.rb
get "things", to: "things#index"

# Add action in controller
# app/controllers/solid_log/things_controller.rb

# Write tests
# test/controllers/solid_log/things_controller_test.rb
```

### Adding a New Configuration Option

```ruby
# Add to lib/solid_log/configuration.rb
attr_accessor :new_option

def initialize
  @new_option = default_value
end

# Document in README.md
# Use in code
SolidLog.configuration.new_option
```

## Release Process

1. Update version in `lib/solid_log/version.rb`
2. Update `CHANGELOG.md`
3. Run full test suite: `bundle exec rake test`
4. Commit changes: `git commit -am "Release v1.0.0"`
5. Create tag: `git tag v1.0.0`
6. Push: `git push && git push --tags`
7. Build gem: `gem build solid_log.gemspec`
8. Publish: `gem push solid_log-1.0.0.gem`

## Troubleshooting Development Issues

### Tests failing with "table not found"

```bash
# Reload schema
cd test/dummy
rails db:schema:load:log

# Or regenerate in-memory schema
# Edit test/test_helper.rb to reload schema
```

### FTS triggers not working

```bash
# Check if triggers exist
sqlite3 test/dummy/storage/test_log.sqlite3
> .schema solid_log_entries_fts
> SELECT * FROM sqlite_master WHERE type='trigger';
```

### Middleware not loading

```bash
# Check engine initialization
# lib/solid_log/engine.rb should include:
initializer "solid_log.middleware" do |app|
  app.middleware.use SolidLog::SilenceMiddleware
end
```

## Getting Help

- **Documentation**: `docs/` directory
- **Tests**: Look at existing tests for examples
- **Issues**: Check GitHub issues for similar problems
- **Discussions**: Start a GitHub discussion for questions

---

Happy developing! 🚀
