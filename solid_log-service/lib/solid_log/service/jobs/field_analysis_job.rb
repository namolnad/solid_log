module SolidLog
  class FieldAnalysisJob
    def self.perform(auto_promote: false)
      SolidLog.without_logging do
        recommendations = FieldAnalyzer.analyze

        if recommendations.any?
          SolidLog::Service.logger.info "SolidLog::FieldAnalysisJob: Found #{recommendations.size} fields for potential promotion"

          recommendations.take(10).each do |rec|
            SolidLog::Service.logger.info "  - #{rec[:field].name} (#{rec[:field].usage_count} uses, priority: #{rec[:priority]})"
          end

          if auto_promote
            promoted_count = FieldAnalyzer.auto_promote_candidates
            SolidLog::Service.logger.info "SolidLog::FieldAnalysisJob: Auto-promoted #{promoted_count} fields"
          end
        else
          SolidLog::Service.logger.info "SolidLog::FieldAnalysisJob: No fields meet promotion threshold"
        end
      end
    end
  end
end
