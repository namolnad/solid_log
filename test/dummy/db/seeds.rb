# Seeds for SolidLog test data
puts "Seeding SolidLog with test data..."

# Generate 100 varied log entries
controllers = [
  "UsersController", "PostsController", "OrdersController", "ProductsController",
  "CommentsController", "SessionsController", "AdminController", "DashboardController",
  "ApiController", "WebhooksController", "PaymentsController", "NotificationsController"
]

actions = [ "index", "show", "create", "update", "destroy", "edit", "new" ]
methods = [ "GET", "POST", "PUT", "PATCH", "DELETE" ]
paths = [
  "/users", "/users/:id", "/posts", "/posts/:id/edit", "/orders/new",
  "/products", "/api/v1/users", "/api/v1/orders", "/admin/dashboard",
  "/payments/checkout", "/webhooks/stripe", "/notifications"
]

messages = [
  "Started %{method} \"%{path}\" for %{ip}",
  "Processing by %{controller}#%{action} as HTML",
  "Processing by %{controller}#%{action} as JSON",
  "Completed %{status} %{status_text} in %{duration}ms (Views: %{view_time}ms | ActiveRecord: %{db_time}ms)",
  "Redirected to %{path}",
  "Rendering layout layouts/application.html.erb",
  "Rendered %{controller}/%{action}.html.erb within layouts/application",
  "User authentication successful for user_id: %{user_id}",
  "Cache miss: %{cache_key}",
  "Cache hit: %{cache_key}",
  "SQL query executed in %{duration}ms",
  "Background job enqueued: %{job_class}",
  "Email sent to %{email}",
  "Payment processed successfully",
  "Validation failed: %{errors}",
  "Exception raised: %{exception}",
  "API rate limit exceeded for IP: %{ip}",
  "Session expired for user_id: %{user_id}",
  "File uploaded: %{filename}",
  "Search query executed: %{query}"
]

error_messages = [
  "NoMethodError: undefined method `name' for nil:NilClass",
  "ActiveRecord::RecordNotFound: Couldn't find User with 'id'=%{id}",
  "ActiveRecord::RecordInvalid: Validation failed: Email can't be blank",
  "ActionController::ParameterMissing: param is missing or the value is empty: user",
  "Timeout::Error: execution expired after 30s",
  "Redis::CannotConnectError: Error connecting to Redis",
  "Net::ReadTimeout: Net::ReadTimeout with #<TCPSocket>",
  "PG::ConnectionBad: connection to server on socket failed",
  "Stripe::CardError: Your card was declined",
  "AWS::S3::Errors::ServiceError: The specified bucket does not exist"
]

ips = (1..20).map { "#{rand(1..255)}.#{rand(1..255)}.#{rand(1..255)}.#{rand(1..255)}" }
user_ids = (1..50).to_a

# Generate entries
100.times do |i|
  # Distribute timestamps over the last 7 days
  timestamp = (Time.current - rand(7.days.to_i).seconds).iso8601

  controller = controllers.sample
  action = actions.sample
  method = methods.sample
  path = paths.sample
  level = if i % 20 == 0
    "error"
  elsif i % 15 == 0
    "warn"
  elsif i % 30 == 0
    "fatal"
  elsif i % 10 == 0
    "debug"
  else
    "info"
  end

  status = if level == "error" || level == "fatal"
    [ 500, 502, 503, 404, 422 ].sample
  elsif level == "warn"
    [ 400, 401, 403, 404 ].sample
  else
    [ 200, 201, 204, 301, 302 ].sample
  end

  duration = rand(10..2000) + rand.round(2)
  ip = ips.sample
  user_id = rand(10) > 2 ? user_ids.sample : nil
  request_id = SecureRandom.uuid

  # Build message based on level
  if level == "error" || level == "fatal"
    message = error_messages.sample % {
      id: rand(1..1000),
      exception: "RuntimeError"
    }
  else
    message_template = messages.sample
    begin
      message = message_template % {
        method: method,
        path: path,
        ip: ip,
        controller: controller,
        action: action,
        status: status,
        status_text: Rack::Utils::HTTP_STATUS_CODES[status] || "Unknown",
        duration: duration.round(1),
        view_time: (duration * 0.6).round(1),
        db_time: (duration * 0.3).round(1),
        user_id: user_id,
        cache_key: "views/#{controller}/#{action}/#{rand(1..100)}",
        job_class: [ "UserMailer", "NotificationJob", "ReportGenerator" ].sample,
        email: "user#{rand(1..100)}@example.com",
        errors: "Email can't be blank, Password is too short",
        filename: "upload_#{rand(1000..9999)}.pdf",
        query: [ "rails", "ruby", "active record", "postgres" ].sample
      }
    rescue KeyError
      # If the message template doesn't use all variables, that's fine
      message = message_template
    end
  end

  # Create log payload
  payload = {
    timestamp: timestamp,
    level: level,
    message: message,
    app: "demo",
    env: "development",
    request_id: request_id,
    duration: duration,
    status_code: status,
    controller: controller,
    action: action,
    path: path,
    method: method,
    ip: ip,
    user_id: user_id
  }

  # Create raw entry (will be parsed by ParserJob)
  SolidLog::RawEntry.create!(
    payload: payload.to_json,
    received_at: Time.current,
    parsed: false
  )

  print "." if i % 10 == 0
end

puts "\n✓ Created 100 log entries"

# Parse the entries immediately
puts "Parsing entries..."
SolidLog::ParserJob.new.perform(batch_size: 100)

puts "✓ Done! You now have 100 varied log entries in your database."
puts "\nSample queries to try:"
puts "  - Filter by level: error"
puts "  - Filter by controller: UsersController"
puts "  - Filter by status code: 500"
puts "  - Search for: 'timeout'"
