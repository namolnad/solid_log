require "thread"

module SolidLog
  module Service
    class Scheduler
      attr_reader :threads, :running

      def initialize(config = SolidLog::Service.configuration)
        @config = config
        @threads = []
        @running = false
        @mutex = Mutex.new
      end

      def start
        return if @running

        @mutex.synchronize do
          return if @running
          @running = true
        end

        SolidLog::Service.logger.info "SolidLog::Service::Scheduler starting..."

        # Parser job - frequent (configurable, default 10s)
        thread = Thread.new { parser_loop }
        thread.abort_on_exception = true
        @threads << thread

        # Cache cleanup - configurable (default hourly)
        thread = Thread.new { cache_cleanup_loop }
        thread.abort_on_exception = true
        @threads << thread

        # Daily jobs - retention and field analysis
        thread = Thread.new { daily_jobs_loop }
        thread.abort_on_exception = true
        @threads << thread

        SolidLog::Service.logger.info "SolidLog::Service::Scheduler started with #{@threads.size} threads"
      end

      def stop
        return unless @running

        SolidLog::Service.logger.info "SolidLog::Service::Scheduler stopping..."

        @mutex.synchronize do
          @running = false
        end

        # Give threads 5 seconds to finish gracefully
        @threads.each { |t| t.join(5) }

        # Force kill any remaining threads
        @threads.each { |t| t.kill if t.alive? }
        @threads.clear

        SolidLog::Service.logger.info "SolidLog::Service::Scheduler stopped"
      end

      def running?
        @running
      end

      private

      def parser_loop
        loop do
          break unless @running

          begin
            SolidLog::ParserJob.perform
          rescue => e
            SolidLog::Service.logger.error "SolidLog::Scheduler: Parser job failed: #{e.message}"
            SolidLog::Service.logger.error e.backtrace.join("\n")
          end

          sleep @config.parser_interval
        end
      end

      def cache_cleanup_loop
        loop do
          break unless @running

          begin
            SolidLog::CacheCleanupJob.perform
          rescue => e
            SolidLog::Service.logger.error "SolidLog::Scheduler: Cache cleanup failed: #{e.message}"
            SolidLog::Service.logger.error e.backtrace.join("\n")
          end

          sleep @config.cache_cleanup_interval
        end
      end

      def daily_jobs_loop
        loop do
          break unless @running

          current_hour = Time.current.hour

          # Run retention job at configured hour (default 2 AM)
          if current_hour == @config.retention_hour
            run_daily_job(:retention)
            sleep 1.hour  # Wait an hour to avoid running multiple times
          end

          # Run field analysis at configured hour (default 3 AM)
          if current_hour == @config.field_analysis_hour
            run_daily_job(:field_analysis)
            sleep 1.hour  # Wait an hour to avoid running multiple times
          end

          # Check every 10 minutes
          sleep 10.minutes
        end
      end

      def run_daily_job(job_name)
        case job_name
        when :retention
          begin
            SolidLog::RetentionJob.perform(
              retention_days: @config.retention_days,
              error_retention_days: @config.error_retention_days
            )
          rescue => e
            SolidLog::Service.logger.error "SolidLog::Scheduler: Retention job failed: #{e.message}"
            SolidLog::Service.logger.error e.backtrace.join("\n")
          end
        when :field_analysis
          begin
            SolidLog::FieldAnalysisJob.perform(
              auto_promote: @config.auto_promote_fields
            )
          rescue => e
            SolidLog::Service.logger.error "SolidLog::Scheduler: Field analysis failed: #{e.message}"
            SolidLog::Service.logger.error e.backtrace.join("\n")
          end
        end
      end
    end
  end
end
