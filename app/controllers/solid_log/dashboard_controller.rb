module SolidLog
  class DashboardController < ApplicationController
    def index
      @health_metrics = SolidLog.without_logging { HealthService.metrics }
      @recent_errors = recent_error_entries
      @log_level_distribution = log_level_distribution
      @field_recommendations = field_recommendations
    end

    private

    def recent_error_entries
      SolidLog.without_logging do
        Entry.errors.recent.limit(10)
      end
    end

    def log_level_distribution
      SolidLog.without_logging do
        Entry.group(:level).count
      end
    end

    def field_recommendations
      SolidLog.without_logging do
        FieldAnalyzer.analyze.take(5)
      end
    end
  end
end
