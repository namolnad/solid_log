module SolidLog
  module Service
    class JobProcessor
      class << self
        attr_reader :scheduler

        def setup
          case configuration.job_mode
          when :scheduler
            setup_scheduler
          when :active_job
            setup_active_job
          when :manual
            setup_manual
          else
            raise ArgumentError, "Invalid job_mode: #{configuration.job_mode}. Must be :scheduler, :active_job, or :manual"
          end
        end

        def stop
          case configuration.job_mode
          when :scheduler
            stop_scheduler
          when :active_job, :manual
            # Nothing to stop
          end
        end

        private

        def configuration
          SolidLog::Service.configuration
        end

        def setup_scheduler
          @scheduler = Scheduler.new(configuration)
          @scheduler.start

          SolidLog::Service.logger.info "SolidLog::Service: Started built-in Scheduler"
          SolidLog::Service.logger.info "  Parser interval: #{configuration.parser_interval}s"
          SolidLog::Service.logger.info "  Cache cleanup interval: #{configuration.cache_cleanup_interval}s"
          SolidLog::Service.logger.info "  Retention hour: #{configuration.retention_hour}:00"
          SolidLog::Service.logger.info "  Field analysis hour: #{configuration.field_analysis_hour}:00"
        end

        def stop_scheduler
          if @scheduler
            @scheduler.stop
            @scheduler = nil
          end
        end

        def setup_active_job
          # Jobs are enqueued via host app's ActiveJob backend
          # Host app should configure recurring jobs using their job backend
          # Example with Solid Queue:
          #
          # SolidQueue::RecurringTask.create!(
          #   key: 'solidlog_parser',
          #   schedule: 'every 10 seconds',
          #   class_name: 'SolidLog::ParserJob'
          # )

          SolidLog::Service.logger.info "SolidLog::Service: Using ActiveJob for background processing"
          SolidLog::Service.logger.info "  Make sure to configure recurring jobs in your host application"
        end

        def setup_manual
          # User manages scheduling via cron or other external scheduler
          # No setup needed

          SolidLog::Service.logger.info "SolidLog::Service: Manual job mode (no auto-scheduling)"
          SolidLog::Service.logger.info "  Set up cron jobs to run:"
          SolidLog::Service.logger.info "    - rails solid_log:parse_logs (every 10 seconds recommended)"
          SolidLog::Service.logger.info "    - rails solid_log:cache_cleanup (hourly recommended)"
          SolidLog::Service.logger.info "    - rails solid_log:retention (daily recommended)"
          SolidLog::Service.logger.info "    - rails solid_log:field_analysis (daily recommended)"
        end
      end
    end
  end
end
