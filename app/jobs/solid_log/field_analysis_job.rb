module SolidLog
  class FieldAnalysisJob < ApplicationJob
    queue_as :default

    def perform(auto_promote: false)
      SolidLog.without_logging do
        recommendations = FieldAnalyzer.analyze

        if recommendations.any?
          Rails.logger.info "SolidLog::FieldAnalysisJob: Found #{recommendations.size} fields for potential promotion"

          recommendations.take(10).each do |rec|
            Rails.logger.info "  - #{rec[:field].name} (#{rec[:field].usage_count} uses, priority: #{rec[:priority]})"
          end

          if auto_promote
            promoted_count = FieldAnalyzer.auto_promote_candidates
            Rails.logger.info "SolidLog::FieldAnalysisJob: Auto-promoted #{promoted_count} fields"
          end
        else
          Rails.logger.info "SolidLog::FieldAnalysisJob: No fields meet promotion threshold"
        end
      end
    end
  end
end
