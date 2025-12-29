# Example: SolidLog UI with IP Whitelist
# Place this in: config/initializers/solid_log_ui.rb

SolidLog::UI.configure do |config|
  config.mode = :direct_db
  config.base_controller = "ActionController::Base"
  config.authentication_method = :custom
end

# IP whitelist authentication
# config/initializers/solid_log_ui_auth.rb
SolidLog::UI::BaseController.class_eval do
  before_action :check_ip_whitelist

  private

  def check_ip_whitelist
    allowed_ips = ENV['SOLIDLOG_ALLOWED_IPS'].to_s.split(',')

    unless allowed_ips.include?(request.remote_ip)
      render plain: "Access denied from IP: #{request.remote_ip}", status: :forbidden
    end
  end
end

# Environment variable:
# SOLIDLOG_ALLOWED_IPS=192.168.1.1,10.0.0.1,127.0.0.1

# Or hardcode for internal network:
# SolidLog::UI::BaseController.class_eval do
#   before_action :check_internal_network
#
#   private
#
#   def check_internal_network
#     ip = IPAddr.new(request.remote_ip)
#     internal_network = IPAddr.new('10.0.0.0/8')
#
#     unless internal_network.include?(ip)
#       render plain: "Access denied - internal network only", status: :forbidden
#     end
#   end
# end

# Combine with other authentication:
# SolidLog::UI::BaseController.class_eval do
#   before_action :check_ip_whitelist
#   before_action :authenticate_user!  # Devise or custom
#   before_action :require_admin
# end
