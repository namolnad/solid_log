# frozen_string_literal: true

module SolidLog
  module Core
    module Jobs
      class FieldAnalysisJob < BaseJob
        queue_as :default

        def perform(auto_promote: false)
          SolidLog.without_logging do
            recommendations = SolidLog::Core::FieldAnalyzer.analyze

            if recommendations.any?
              logger.info "SolidLog::FieldAnalysisJob: Found #{recommendations.size} fields for potential promotion"

              recommendations.take(10).each do |rec|
                logger.info "  - #{rec[:field].name} (#{rec[:field].usage_count} uses, priority: #{rec[:priority]})"
              end

              if auto_promote
                promoted_count = SolidLog::Core::FieldAnalyzer.auto_promote_candidates
                logger.info "SolidLog::FieldAnalysisJob: Auto-promoted #{promoted_count} fields"
              end
            else
              logger.info "SolidLog::FieldAnalysisJob: No fields meet promotion threshold"
            end
          end
        rescue => e
          logger.error "SolidLog::FieldAnalysisJob failed: #{e.message}"
          # Re-raise for ActiveJob retry if available, otherwise just log
          raise if defined?(ActiveJob::Base)
        end

        private

        def logger
          defined?(SolidLog) && SolidLog.respond_to?(:logger) ? SolidLog.logger : Logger.new(STDOUT)
        end
      end
    end
  end
end
