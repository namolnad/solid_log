module SolidLog
  class FieldAnalyzer
    PROMOTION_THRESHOLD = 1000 # Fields with 1000+ uses are candidates

    def self.analyze
      SolidLog.without_logging do
        hot_fields = Field.where("usage_count >= ?", PROMOTION_THRESHOLD)
                          .where(promoted: false)
                          .order(usage_count: :desc)

        recommendations = hot_fields.map do |field|
          {
            field: field,
            usage_count: field.usage_count,
            recommendation: recommend_action(field),
            priority: calculate_priority(field)
          }
        end

        recommendations.sort_by { |r| -r[:priority] }
      end
    end

    def self.auto_promote_candidates
      candidates = analyze.select { |r| r[:priority] >= 8 }

      candidates.each do |recommendation|
        field = recommendation[:field]
        field.promote!
        Rails.logger.info "SolidLog: Auto-promoted field '#{field.name}' (#{field.usage_count} uses)"
      end

      candidates.size
    end

    private

    def self.recommend_action(field)
      case field.field_type
      when "string"
        if field.usage_count > 10000
          "Strongly recommend promotion to indexed TEXT column"
        else
          "Consider promotion to TEXT column"
        end
      when "number"
        "Recommend promotion to REAL or INTEGER column for numeric queries"
      when "boolean"
        "Recommend promotion to BOOLEAN column for filtering"
      when "datetime"
        "Strongly recommend promotion to DATETIME column for time-based queries"
      else
        "Keep in JSON - type too complex for promotion"
      end
    end

    def self.calculate_priority(field)
      priority = 0

      # Usage count score (0-5 points)
      priority += 1 if field.usage_count > 1000
      priority += 1 if field.usage_count > 5000
      priority += 1 if field.usage_count > 10000
      priority += 1 if field.usage_count > 50000
      priority += 1 if field.usage_count > 100000

      # Type score (0-3 points)
      priority += 3 if field.field_type.in?(%w[datetime number])
      priority += 2 if field.field_type == "boolean"
      priority += 1 if field.field_type == "string"

      # Recency score (0-2 points)
      if field.last_seen_at && field.last_seen_at > 1.day.ago
        priority += 2
      elsif field.last_seen_at && field.last_seen_at > 7.days.ago
        priority += 1
      end

      priority
    end
  end
end
