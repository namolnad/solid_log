# frozen_string_literal: true

module SolidLog
  module Core
    module Jobs
      # Conditionally inherit from ActiveJob if available
      # This allows the same job class to work in Rails apps AND solid_log-service
      if defined?(ActiveJob::Base)
        BaseJob = ActiveJob::Base
      else
        # Plain Ruby class when ActiveJob not available
        BaseJob = Class.new do
          def self.queue_as(*_args)
            # No-op when not using ActiveJob
          end

          def self.perform_later(*args, **kwargs)
            # Synchronous execution when ActiveJob not available
            new.perform(*args, **kwargs)
          end

          def self.perform_now(*args, **kwargs)
            new.perform(*args, **kwargs)
          end
        end
      end
    end
  end
end
