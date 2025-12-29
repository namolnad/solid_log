class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Disabled in test environment to avoid blocking test requests
  allow_browser versions: :modern if Rails.env.production?
end
