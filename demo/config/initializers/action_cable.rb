# Action Cable configuration for SolidLog UI live tail
Rails.application.config.action_cable.mount_path = "/cable"
Rails.application.config.action_cable.url = "ws://localhost:3000/cable"

# Allow requests from localhost for development
Rails.application.config.action_cable.allowed_request_origins = [
  "http://localhost:3000",
  /http:\/\/localhost:.*/
]

# Disable request forgery protection for Action Cable (development only)
Rails.application.config.action_cable.disable_request_forgery_protection = true if Rails.env.development? || Rails.env.test?
