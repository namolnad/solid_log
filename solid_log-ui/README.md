##SolidLog::UI

Mission Control-style web interface for viewing SolidLog entries. Supports both direct database access and HTTP API mode.

## Overview

`solid_log-ui` provides:

- **Mission Control-style UI**: Browse, filter, and search logs
- **Dual-mode support**:
  - **Direct DB**: Fast access when UI and service share database
  - **HTTP API**: Remote access when service runs separately
- **Overridable authentication**: Easy integration with your auth system
- **Real-time updates**: Live tail support (WebSocket or polling)
- **Full-text search**: Powered by database-native FTS
- **Request/job correlation**: Timeline views for related logs

## Installation

```ruby
gem 'solid_log-ui'

# Also install database adapter if using direct_db mode
gem 'sqlite3', '>= 2.1'   # or pg, or mysql2
```

## Configuration

Create `config/initializers/solid_log_ui.rb`:

### Direct DB Mode (Default)

```ruby
SolidLog::UI.configure do |config|
  config.mode = :direct_db
  config.authentication_method = :custom  # Override BaseController
  config.stream_view_style = :compact
  config.per_page = 100
end
```

### HTTP API Mode

```ruby
SolidLog::UI.configure do |config|
  config.mode = :http_api
  config.service_url = ENV['SOLIDLOG_SERVICE_URL']
  config.service_token = ENV['SOLIDLOG_SERVICE_TOKEN']
  config.authentication_method = :custom
end
```

## Mount in Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount SolidLog::UI::Engine => "/admin/logs"
end
```

Access at: `http://yourapp.com/admin/logs`

## Authentication

The `BaseController` is designed to be easily overridden in your host application.

### Option 1: Reopen the Class (Recommended)

Create `config/initializers/solid_log_ui_auth.rb`:

```ruby
# Use your existing authentication system
SolidLog::UI::BaseController.class_eval do
  before_action :require_admin

  private

  def require_admin
    redirect_to root_path unless current_user&.admin?
  end

  # Override current_user to use your app's authentication
  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
```

### Option 2: HTTP Basic Auth

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.authentication_method = :basic
end

# Store credentials in Rails credentials
# rails credentials:edit
solidlog:
  username: admin
  password: secret_password
```

Or override the auth method:

```ruby
SolidLog::UI::BaseController.class_eval do
  protected

  def authenticate_with_basic_auth(username, password)
    username == ENV['ADMIN_USER'] && password == ENV['ADMIN_PASSWORD']
  end
end
```

### Option 3: Devise Integration

```ruby
SolidLog::UI::BaseController.class_eval do
  before_action :authenticate_admin_user!

  private

  def authenticate_admin_user!
    authenticate_user!
    redirect_to root_path unless current_user.admin?
  end

  # Devise provides current_user automatically
end
```

### Option 4: Custom Middleware

```ruby
SolidLog::UI::BaseController.class_eval do
  before_action :check_api_key

  private

  def check_api_key
    api_key = request.headers['X-Admin-API-Key']
    head :unauthorized unless api_key == ENV['ADMIN_API_KEY']
  end
end
```

### Option 5: IP Whitelist

```ruby
SolidLog::UI::BaseController.class_eval do
  before_action :check_ip_whitelist

  private

  def check_ip_whitelist
    allowed_ips = ENV['ALLOWED_IPS'].to_s.split(',')
    unless allowed_ips.include?(request.remote_ip)
      render plain: "Access denied", status: :forbidden
    end
  end
end
```

## Deployment Modes

### Mode 1: Direct DB (Fast, Same Host)

**Use when**: UI and service run on same host with shared database

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.mode = :direct_db
end

# config/database.yml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
  log:
    adapter: sqlite3
    database: storage/production_log.sqlite3  # Shared with service
    migrations_paths: db/log_migrate
```

**Benefits:**
- ✅ Fastest (direct database queries)
- ✅ No HTTP overhead
- ✅ Works with shared volume in Kamal

### Mode 2: HTTP API (Flexible, Remote)

**Use when**: Service runs separately from main app

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.mode = :http_api
  config.service_url = 'http://solidlog-service:3001'
  config.service_token = ENV['SOLIDLOG_TOKEN']
end
```

**Benefits:**
- ✅ Service can run independently
- ✅ UI can be in separate app/server
- ✅ Works across network boundaries

## Features

### Streams View
- Filter by level, app, env, controller, action, path, method, status
- Full-text search
- Compact or expanded view modes
- Live tail (auto-refresh)

### Entry Details
- Full log entry with all fields
- JSON-formatted extra fields
- Copy to clipboard
- Related entries (request/job correlation)

### Timelines
- Request timeline: All logs for a request_id
- Job timeline: All logs for a job_id
- Duration visualization
- Level distribution

### Dashboard
- Recent error rate
- Ingestion metrics
- Parse backlog status
- Database size
- Health indicators

## Helper Methods

Available in all UI views:

```erb
<% if current_user %>
  Welcome, <%= current_user.email %>
<% end %>

<%= level_badge(entry.level) %>
<%= duration_badge(entry.duration) %>
<%= status_code_badge(entry.status_code) %>
```

## Customizing Views

Override views by creating matching files in your app:

```
app/views/solid_log/ui/
├── streams/
│   └── index.html.erb       # Override streams view
├── entries/
│   └── show.html.erb        # Override entry detail view
└── layouts/
    └── solid_log/
        └── ui/
            └── application.html.erb  # Override layout
```

## Customizing Styles

Add custom CSS in your application:

```css
/* app/assets/stylesheets/solid_log_custom.css */
.solid-log-stream-entry {
  border-left: 4px solid #your-brand-color;
}
```

Then import in your application.css:

```css
@import "solid_log_custom";
```

## Development

```bash
cd solid_log-ui
bundle install
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
