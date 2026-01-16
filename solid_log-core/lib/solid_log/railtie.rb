# frozen_string_literal: true

require "rails/railtie"

module SolidLog
  class Railtie < Rails::Railtie
    # Silence SolidLog's internal operations in ALL environments
    # This prevents noise from SolidLog's own SQL queries, transactions, and view rendering
    initializer "solid_log.silence_internal_logs", after: :load_config_initializers do
      ActiveSupport.on_load(:active_record) do
        SolidLog::Railtie.silence_sql_and_transaction_logs
      end
    end

    # Silence view logs after Rails has fully initialized
    # This ensures ActionView::LogSubscriber is loaded and instantiated
    config.after_initialize do
      SolidLog::Railtie.silence_view_rendering_logs
    end

    class << self
      def silence_view_rendering_logs
        return unless defined?(ActionView::LogSubscriber)

        # Silence "Rendering..." messages (logged at start)
        ActionView::LogSubscriber::Start.prepend(Module.new do
          def start(name, id, payload)
            return if payload[:identifier]&.include?("solid_log")
            super
          end
        end) if defined?(ActionView::LogSubscriber::Start)

        # Silence "Rendered..." messages (logged at completion)
        ActionView::LogSubscriber.prepend(Module.new do
          def render_template(event)
            return if event.payload[:identifier]&.include?("solid_log")
            super
          end

          def render_layout(event)
            return if event.payload[:identifier]&.include?("solid_log")
            super
          end

          def render_partial(event)
            return if event.payload[:identifier]&.include?("solid_log")
            super
          end
        end)
      end

      def silence_sql_and_transaction_logs
        return unless defined?(ActiveRecord::LogSubscriber)

        ActiveRecord::LogSubscriber.prepend(Module.new do
          def sql(event)
            # Skip SolidLog table queries
            sql_query = event.payload[:sql]
            return if sql_query&.match?(/solid_log_(entries|raw|fields|facet_cache|tokens)/i)
            return if event.payload[:name]&.include?("SolidLog")

            # Skip all transaction logs (BEGIN/COMMIT/ROLLBACK)
            return if event.payload[:name] == "TRANSACTION" && Rails.env.development?

            super
          end
        end)
      end
    end
  end
end
