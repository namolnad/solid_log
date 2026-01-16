# frozen_string_literal: true

module SolidLog
  module Core
    module Jobs
      # ParseJob processes batches of unparsed raw log entries.
      #
      # This job can be used in three contexts:
      # 1. Rails app with Solid Queue (scheduled in config/recurring.yml)
      # 2. Rails app with other ActiveJob backends (Sidekiq, Resque, etc.)
      # 3. solid_log-service without Rails (called directly)
      #
      # @example Solid Queue (config/recurring.yml)
      #   solidlog_parse:
      #     class: SolidLog::Core::Jobs::ParseJob
      #     schedule: every 10 seconds
      #     args: [{ batch_size: 200 }]
      #
      # @example Direct call (service)
      #   SolidLog::Core::Jobs::ParseJob.perform_now(batch_size: 200)
      class ParseJob < BaseJob
        queue_as :default

        # Process a batch of unparsed raw entries
        #
        # @param batch_size [Integer] Number of entries to process (default: config value)
        # @return [Hash] Statistics hash with :processed, :inserted, :errors keys
        def perform(batch_size: nil)
          batch_size ||= SolidLog.configuration.parser_batch_size

          # Delegate to BatchParsingService
          stats = SolidLog::Core::Services::BatchParsingService.process_batch(
            batch_size: batch_size,
            logger: logger,
            broadcast_callback: method(:broadcast_callback)
          )

          # Log results if entries were processed
          if stats[:processed] > 0
            logger.info "SolidLog::ParseJob: Processed #{stats[:processed]}, inserted #{stats[:inserted]}, errors #{stats[:errors]}"
          end

          stats
        rescue => e
          logger.error "SolidLog::ParseJob failed: #{e.class} - #{e.message}"
          logger.error e.backtrace.first(10).join("\n") if e.backtrace

          # Re-raise for ActiveJob retry if available, otherwise just log
          raise if defined?(ActiveJob::Base) && self.class.ancestors.include?(ActiveJob::Base)

          stats || { processed: 0, inserted: 0, errors: 1 }
        end

        private

        # Get logger instance
        def logger
          if defined?(SolidLog) && SolidLog.respond_to?(:logger)
            SolidLog.logger
          else
            Logger.new($stdout).tap { |log| log.level = Logger::INFO }
          end
        end

        # Broadcast callback for ActionCable
        def broadcast_callback(entry_ids)
          return if entry_ids.empty?

          if defined?(ActionCable) && ActionCable.server
            ActionCable.server.broadcast(
              "solid_log_new_entries",
              { entry_ids: entry_ids }
            )
            logger.debug "SolidLog::ParseJob: Broadcasted #{entry_ids.size} entries via ActionCable"
          end
        rescue => e
          # Silent failure - broadcasting is optional
          logger.debug "SolidLog::ParseJob: Broadcast failed: #{e.message}"
        end
      end
    end
  end
end
