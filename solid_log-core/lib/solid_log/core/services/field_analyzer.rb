module SolidLog
  module Core
    class FieldAnalyzer
      # Analyze fields and return promotion recommendations
      def self.analyze(threshold: 1000)
        recommendations = []

        # Get hot fields that are not yet promoted
        hot_fields = Field
          .hot_fields(threshold)
          .unpromoted
          .recently_seen(30) # Only consider fields seen in last 30 days

        hot_fields.each do |field|
          # Calculate priority score
          priority = calculate_priority(field, threshold)

          recommendations << {
            field: field,
            priority: priority,
            reason: promotion_reason(field, threshold)
          }
        end

        # Sort by priority (highest first)
        recommendations.sort_by { |rec| -rec[:priority] }
      end

      # Auto-promote fields that meet the threshold
      def self.auto_promote_candidates(threshold: 1000)
        candidates = analyze(threshold: threshold)
        promoted_count = 0

        candidates.each do |candidate|
          field = candidate[:field]

          # Only auto-promote fields with high priority
          if candidate[:priority] >= 80
            SolidLog.logger.info "FieldAnalyzer: Auto-promoting field '#{field.name}' (usage: #{field.usage_count}, priority: #{candidate[:priority]})"

            field.promote!
            promoted_count += 1

            # TODO: In real implementation, we would need to:
            # 1. Generate migration to add column
            # 2. Backfill existing data
            # 3. Update queries to use promoted field
            # For now, just mark as promoted
          end
        end

        promoted_count
      end

      private

      # Calculate promotion priority (0-100 scale)
      def self.calculate_priority(field, threshold)
        score = 0

        # Usage score (0-50 points)
        usage_score = [50, (field.usage_count.to_f / (threshold * 10) * 50).to_i].min
        score += usage_score

        # Recency score (0-25 points)
        days_since_seen = (Time.current - field.last_seen_at) / 1.day
        recency_score = [0, [25, (25 - days_since_seen).to_i].min].max
        score += recency_score

        # Type score (0-25 points)
        # Favor simple types that are easier to index
        type_score = case field.field_type
        when "string", "number", "boolean"
                      25
        when "datetime"
                      20
        else
                      10
        end
        score += type_score

        [100, score].min
      end

      # Generate human-readable reason for promotion
      def self.promotion_reason(field, threshold)
        reasons = []

        if field.usage_count >= threshold * 10
          reasons << "extremely high usage (#{field.usage_count})"
        elsif field.usage_count >= threshold * 5
          reasons << "very high usage (#{field.usage_count})"
        else
          reasons << "high usage (#{field.usage_count})"
        end

        days_since_seen = (Time.current - field.last_seen_at) / 1.day
        if days_since_seen < 1
          reasons << "actively used today"
        elsif days_since_seen < 7
          reasons << "recently active"
        end

        reasons.join(", ")
      end
    end
  end
end
