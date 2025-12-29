# Example: SolidLog UI with Devise Authentication
# Place this in: config/initializers/solid_log_ui.rb

SolidLog::UI.configure do |config|
  config.mode = :direct_db
  config.base_controller = "ApplicationController"  # Has Devise
  config.authentication_method = :custom
end

# Your ApplicationController already has Devise:
# class ApplicationController < ActionController::Base
#   before_action :authenticate_user!
#
#   # Devise provides current_user automatically
# end

# Optional: Require admin access
# config/initializers/solid_log_ui_auth.rb
SolidLog::UI::BaseController.class_eval do
  before_action :require_admin

  private

  def require_admin
    unless current_user&.admin?
      flash[:alert] = "You must be an admin to access logs"
      redirect_to root_path
    end
  end
end

# Or use Pundit for authorization:
# SolidLog::UI::BaseController.class_eval do
#   include Pundit
#   before_action :authorize_log_access
#
#   private
#
#   def authorize_log_access
#     authorize :solid_log, :view?
#   end
# end
#
# Then in app/policies/solid_log_policy.rb:
# class SolidLogPolicy
#   attr_reader :user, :record
#
#   def initialize(user, record)
#     @user = user
#   end
#
#   def view?
#     user.admin?
#   end
# end
