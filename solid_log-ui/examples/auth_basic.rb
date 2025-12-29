# Example: SolidLog UI with HTTP Basic Authentication
# Place this in: config/initializers/solid_log_ui.rb

SolidLog::UI.configure do |config|
  config.mode = :direct_db
  config.authentication_method = :basic
end

# Store credentials in Rails encrypted credentials:
# rails credentials:edit
#
# Add:
# solidlog:
#   username: admin
#   password: super_secret_password

# Or override to use environment variables:
# config/initializers/solid_log_ui_auth.rb
SolidLog::UI::BaseController.class_eval do
  protected

  def authenticate_with_basic_auth(username, password)
    username == ENV['SOLIDLOG_USERNAME'] && password == ENV['SOLIDLOG_PASSWORD']
  end
end

# Or use a simple hardcoded check (development only):
# SolidLog::UI::BaseController.class_eval do
#   protected
#
#   def authenticate_with_basic_auth(username, password)
#     username == 'admin' && password == 'changeme'
#   end
# end

# Access will prompt for username/password in browser
