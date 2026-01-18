# Base Controller Configuration

The `SolidLog::UI::BaseController` can inherit from any controller class in your application.

## Setting the Base Controller

In your `config/initializers/solid_log_ui.rb`:

```ruby
SolidLog::UI.configure do |config|
  # Inherit from your app's ApplicationController
  config.base_controller = "ApplicationController"

  # Or any other controller
  config.base_controller = "AdminController"
  config.base_controller = "API::BaseController"
end
```

## Why This Matters

By inheriting from your app's controller, SolidLog::UI automatically gains:

- ✅ Your authentication system (Devise, Sorcery, custom, etc.)
- ✅ Your authorization logic (Pundit, CanCanCan, etc.)
- ✅ Your before_actions and filters
- ✅ Your helper methods
- ✅ Your exception handling
- ✅ Your CSRF protection settings

## Examples

### Example 1: Inherit from ApplicationController with Devise

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.base_controller = "ApplicationController"
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!  # Devise

  def current_user
    super  # Devise provides this
  end
end
```

Now all SolidLog::UI controllers automatically require authentication via Devise!

### Example 2: Inherit from AdminController

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.base_controller = "AdminController"
end

# app/controllers/admin_controller.rb
class AdminController < ApplicationController
  before_action :require_admin!

  private

  def require_admin!
    redirect_to root_path unless current_user&.admin?
  end
end
```

Now all SolidLog::UI controllers require admin access!

### Example 3: API-only Application

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.base_controller = "ActionController::API"  # For API-only apps
end
```

### Example 4: Custom Base with IP Whitelist

```ruby
# app/controllers/secure_controller.rb
class SecureController < ActionController::Base
  before_action :check_ip_whitelist

  private

  def check_ip_whitelist
    allowed_ips = ENV['ADMIN_IPS'].to_s.split(',')
    head :forbidden unless allowed_ips.include?(request.remote_ip)
  end
end

# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.base_controller = "SecureController"
end
```

## Still Need More Control?

If inheriting from your base controller isn't enough, you can still reopen `SolidLog::UI::BaseController`:

```ruby
# config/initializers/solid_log_ui.rb
SolidLog::UI.configure do |config|
  config.base_controller = "ApplicationController"
end

# Add additional before_actions specific to SolidLog
SolidLog::UI::BaseController.class_eval do
  before_action :log_access
  before_action :check_feature_flag

  private

  def log_access
    Rails.logger.info "#{current_user&.email} accessed SolidLog at #{Time.current}"
  end

  def check_feature_flag
    head :not_found unless FeatureFlag.enabled?(:solid_log_ui)
  end
end
```

## Default Behavior

If you don't set `config.base_controller`, it defaults to `"ActionController::Base"`.

This ensures SolidLog::UI works out of the box, but you should configure it to match your app's architecture.
