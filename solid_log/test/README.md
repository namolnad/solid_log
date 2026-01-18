# SolidLog UI Tests

This directory contains comprehensive tests for the SolidLog UI gem.

## Test Structure

```
test/
├── test_helper.rb           # Test configuration and helpers
├── fixtures/                # Test data
│   ├── solid_log_entries.yml
│   ├── solid_log_fields.yml
│   └── solid_log_tokens.yml
├── controllers/             # Controller tests
│   ├── dashboard_controller_test.rb
│   ├── streams_controller_test.rb
│   ├── entries_controller_test.rb
│   ├── fields_controller_test.rb
│   ├── timelines_controller_test.rb
│   └── tokens_controller_test.rb
├── channels/                # ActionCable channel tests
│   └── log_stream_channel_test.rb
└── helpers/                 # View helper tests
    ├── application_helper_test.rb
    ├── dashboard_helper_test.rb
    ├── entries_helper_test.rb
    └── timeline_helper_test.rb
```

## Running Tests

From the dummy app directory:

```bash
cd test/dummy
bundle exec rails test ../../test/controllers/dashboard_controller_test.rb
```

Or run all tests:

```bash
cd test/dummy
bundle exec rails test ../../test/**/*_test.rb
```

## Test Coverage

### Controllers
- **DashboardController**: Health metrics, recent errors, log level distribution
- **StreamsController**: Log streaming, filtering, pagination, timeline generation
- **EntriesController**: Entry details, correlation tracking
- **FieldsController**: Field management, promotion/demotion, filter type updates
- **TimelinesController**: Request and job timelines
- **TokensController**: API token CRUD operations

### Channels
- **LogStreamChannel**: WebSocket subscriptions, filtering, broadcasting

### Helpers
- **ApplicationHelper**: Badge rendering, formatting, correlation links
- **DashboardHelper**: Count formatting, percentages, trend indicators
- **EntriesHelper**: JSON prettification
- **TimelineHelper**: Duration bars, event icons, timeline formatting

## Fixtures

Test fixtures are provided for:
- **Entries**: Error, info, debug, and warn level entries with various attributes
- **Fields**: Promoted and unpromoted fields with different types
- **Tokens**: Sample API tokens for authentication testing
