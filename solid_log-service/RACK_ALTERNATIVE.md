# Pure Rack Alternative Architecture

This document sketches out how `solid_log-service` could be built with pure Rack instead of Rails, for ultra-lightweight deployments.

## Dependencies (Rack-only)

```ruby
# solid_log-service.gemspec (Rack version)
spec.add_dependency "solid_log-core", "~> 0.1.0"
spec.add_dependency "rack", "~> 3.0"
spec.add_dependency "puma", "~> 6.0"
spec.add_dependency "rack-router"  # or build simple router
spec.add_dependency "json"
```

**Weight comparison:**
- **Current (with Rails)**: ~50MB of dependencies
- **Rack version**: ~5-10MB of dependencies

## Rack Application Structure

```ruby
# lib/solid_log/service/rack_app.rb
require 'rack'
require 'json'
require 'solid_log/core'

module SolidLog
  module Service
    class RackApp
      def call(env)
        request = Rack::Request.new(env)

        # Simple router
        case [request.request_method, request.path_info]
        when ['POST', '/api/v1/ingest']
          handle_ingest(request)
        when ['GET', '/api/v1/entries']
          handle_entries_index(request)
        when ['GET', %r{^/api/v1/entries/(\d+)$}]
          handle_entries_show($1)
        when ['POST', '/api/v1/search']
          handle_search(request)
        when ['GET', '/api/v1/health']
          handle_health(request)
        else
          [404, {'Content-Type' => 'application/json'}, [json_response({error: 'Not found'})]]
        end
      rescue => e
        [500, {'Content-Type' => 'application/json'}, [json_response({error: e.message})]]
      end

      private

      def handle_ingest(request)
        # Authenticate
        token = authenticate_token(request)
        return unauthorized unless token

        # Parse body
        body = JSON.parse(request.body.read)

        # Create raw entry
        raw_entry = SolidLog::RawEntry.create!(
          token_id: token.id,
          payload: body.to_json
        )

        [200, json_headers, [json_response({status: 'accepted', id: raw_entry.id})]]
      end

      def handle_entries_index(request)
        params = request.params

        # Build query using SearchService
        entries = SolidLog::SearchService.query(
          level: params['level'],
          app: params['app'],
          env: params['env'],
          query: params['q']
        ).recent.limit(params['limit'] || 100)

        [200, json_headers, [json_response({
          entries: entries.as_json(methods: [:extra_fields_hash]),
          total: entries.count
        })]]
      end

      def handle_entries_show(id)
        entry = SolidLog::Entry.find(id)
        [200, json_headers, [json_response({entry: entry.as_json(methods: [:extra_fields_hash])})]]
      rescue ActiveRecord::RecordNotFound
        [404, json_headers, [json_response({error: 'Not found'})]]
      end

      def handle_search(request)
        body = JSON.parse(request.body.read)
        query = body['q'] || body['query']

        return [400, json_headers, [json_response({error: 'Query required'})]] if query.blank?

        entries = SolidLog::SearchService.search(query).recent.limit(100)

        [200, json_headers, [json_response({
          query: query,
          entries: entries.as_json(methods: [:extra_fields_hash])
        })]]
      end

      def handle_health(request)
        metrics = SolidLog::HealthService.metrics
        status_code = metrics[:parsing][:health_status] == 'critical' ? 503 : 200

        [status_code, json_headers, [json_response({
          status: metrics[:parsing][:health_status],
          timestamp: Time.current.iso8601,
          metrics: metrics
        })]]
      end

      def authenticate_token(request)
        auth_header = request.get_header('HTTP_AUTHORIZATION')
        return nil unless auth_header&.start_with?('Bearer ')

        token_value = auth_header.sub('Bearer ', '')
        SolidLog::Token.authenticate(token_value)
      end

      def unauthorized
        [401, json_headers, [json_response({error: 'Unauthorized'})]]
      end

      def json_headers
        {'Content-Type' => 'application/json'}
      end

      def json_response(data)
        JSON.generate(data)
      end
    end
  end
end
```

## config.ru (Rack version)

```ruby
require 'solid_log/core'
require 'solid_log/service'
require_relative 'lib/solid_log/service/rack_app'

# Database setup
ActiveRecord::Base.establish_connection(
  adapter: ENV['DB_ADAPTER'] || 'sqlite3',
  database: ENV['DATABASE_URL'] || 'storage/production_log.sqlite3'
)

# Start job processor
SolidLog::Service.start!

# Shutdown hook
at_exit { SolidLog::Service.stop! }

# Run Rack app
run SolidLog::Service::RackApp.new
```

## Job Processing (Rack version)

Same as current - Scheduler, JobProcessor work identically since they only depend on `solid_log-core` (which has ActiveJob).

## CLI (Rack version)

```ruby
#!/usr/bin/env ruby
# bin/solid_log_service

require 'bundler/setup'
require 'rack'

options = {
  port: ENV['PORT'] || 3001,
  bind: ENV['BIND'] || '0.0.0.0'
}

puts "Starting SolidLog Service (Rack)..."
puts "  Binding: #{options[:bind]}:#{options[:port]}"

# Load config.ru
app, options_from_ru = Rack::Builder.parse_file('config.ru')

# Run with Puma
require 'puma/cli'
Puma::CLI.new([
  '--bind', "tcp://#{options[:bind]}:#{options[:port]}",
  '--workers', ENV.fetch('WEB_CONCURRENCY', '2'),
  '--threads', "#{ENV.fetch('MIN_THREADS', '5')}:#{ENV.fetch('MAX_THREADS', '5')}"
]).run
```

## Pros & Cons

### Rack Version Pros:
- **Lighter**: ~80% smaller dependency footprint
- **Faster startup**: No Rails initialization overhead
- **Simpler**: Fewer abstractions, clearer control flow
- **Lower memory**: ~30-50MB less RAM usage

### Rack Version Cons:
- **More code**: Manual routing, middleware, error handling
- **Less familiar**: Not standard Rails patterns
- **Duplicate logic**: Need to reimplement controller helpers
- **No ActiveJob integration**: Jobs run, but harder to integrate with host app's queue
- **ActionCable integration**: Requires standalone setup (still works, just needs configuration)

## When to Use Each

### Use Rails version (current):
- **Primary deployment scenario**: Bundled with existing Rails app via Kamal
- **ActiveJob integration**: Want to use host app's Solid Queue/Sidekiq
- **Rapid development**: Leverage Rails conventions
- **Team familiarity**: Team knows Rails

### Use Rack version:
- **Standalone microservice**: Truly independent service
- **Resource-constrained**: Running on minimal hardware
- **High-density deployment**: Many service instances per host
- **Pure API**: No need for Rails features

## Implementation Status

**Current**: Rails-based (implemented in Phase 2)

**Rack version**: Sketch only (could be implemented if needed)

## Migration Path

If desired, we could:

1. Create `solid_log-service-rack` as separate gem
2. Share same core (`solid_log-core`)
3. Users choose which service gem to install
4. Same configuration API, just different runtime

```ruby
# Rails version
gem 'solid_log-service'

# OR Rack version (lighter)
gem 'solid_log-service-rack'
```

Both would work identically from client perspective.

## ActionCable with Rack (Live-Tailing Support)

**Important**: ActionCable is **REQUIRED** for live-tailing functionality and works standalone with Rack.

### Setup in Rack Version

1. **Add dependency** to gemspec:
```ruby
spec.add_dependency "actioncable", "~> 8.0"
```

2. **Mount ActionCable** in `rack_app.rb`:
```ruby
# Add to router
when ['GET', '/cable']
  ActionCable.server.call(env)
```

3. **Configure in config.ru**:
```ruby
require 'action_cable/engine'

# Load cable configuration
cable_config = YAML.load_file('config/cable.yml')[ENV['RAILS_ENV'] || 'production']
ActionCable.server.config.cable = cable_config
ActionCable.server.config.logger = SolidLog::Service.logger
```

4. **Keep config/cable.yml**:
```yaml
production:
  adapter: async  # or redis for multi-process
```

5. **Broadcasting remains unchanged**:
```ruby
# In parser job
ActionCable.server.broadcast(
  "solid_log_new_entries",
  { entry_ids: new_entry_ids }
)
```

### Memory Impact

- ActionCable adds ~5-10MB to memory footprint
- Total with Rack + ActionCable: ~15-25MB (still 60-70% savings vs Rails)
- Without ActionCable: ~5-10MB

### Testing ActionCable

Ensure live-tailing works after conversion:
```ruby
# Test WebSocket connection
ws = Faraday.new('ws://localhost:3001/cable')
ws.get # Should upgrade to WebSocket
```
