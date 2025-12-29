require_relative 'lib/solid_log/service'
require_relative 'lib/solid_log/service/application'

# Load routes
require_relative 'config/routes'

run SolidLog::Service::Application
