require 'rails/railtie'
require 'rails_semantic_logger'

module RailsSemanticLogging
  class Railtie < Rails::Railtie
    config.before_configuration do
      $stdout.sync = true if RailsSemanticLogging.config.stdout_sync
    end

    # Runs BEFORE the upstream rails_semantic_logger Engine's :initialize_logger initializer.
    # This ensures our configuration is applied before the logger is set up.
    initializer 'rails_semantic_logging.configure', before: :initialize_logger do |app|
      cfg = RailsSemanticLogging.config

      # Configure rails_semantic_logger options
      app.config.rails_semantic_logger.quiet_assets = cfg.quiet_assets
      app.config.rails_semantic_logger.console_logger = false
      app.config.rails_semantic_logger.add_file_appender = false

      # Set formatter based on environment
      app.config.rails_semantic_logger.format = cfg.formatter_for(Rails.env)

      # Merge default tags (request_id, client_ip) with app-specific custom tags
      app.config.log_tags = cfg.effective_log_tags

      # Set log level based on environment, respecting LOG_LEVEL env var
      app.config.log_level = cfg.log_level_for(Rails.env)

      # Add stdout appender with the configured formatter.
      # IMPORTANT: Do NOT pass level: parameter. Subscriber#level defaults to :trace
      # when unset, which is required by the host app's spec/support/output.rb check.
      app.config.semantic_logger.add_appender(io: $stdout, formatter: app.config.rails_semantic_logger.format)
    end

    config.to_prepare do
      cfg = RailsSemanticLogging.config
      SemanticLogger.application = cfg.application_name || Rails.application.class.module_parent_name
      SemanticLogger.environment = cfg.environment_name || Rails.env
      SemanticLogger.sync! if Rails.env.test? && cfg.sync_in_test
    end

    config.after_initialize do
      # Include DefaultPayload in ActionController to enrich request logs
      # with host, user_agent, and referer (mapped to http.* by Datadog formatter)
      if RailsSemanticLogging.config.default_payload
        require 'rails_semantic_logging/action_controller/default_payload'

        ActiveSupport.on_load(:action_controller_base) do
          include RailsSemanticLogging::ActionController::DefaultPayload
        end
        ActiveSupport.on_load(:action_controller_api) do
          include RailsSemanticLogging::ActionController::DefaultPayload
        end
      end

      # Apply ActiveJob logging patch for named tags
      ActiveSupport.on_load(:active_job) do
        require 'rails_semantic_logging/job_logging/active_job_patch'
        prepend RailsSemanticLogging::JobLogging::ActiveJobPatch
      end

      # Apply Sidekiq logging patch if Sidekiq is loaded
      if defined?(::Sidekiq::JobLogger)
        require 'sidekiq/job_logger'
        require 'rails_semantic_logging/job_logging/sidekiq_patch'
        ::Sidekiq::JobLogger.prepend(RailsSemanticLogging::JobLogging::SidekiqPatch)
      end

      # Apply Datadog log injection patch if Datadog tracing is loaded
      if defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection)
        require 'rails_semantic_logging/datadog/log_injection'
        RailsSemanticLogging::Datadog::LogInjection.apply!
      end
    end
  end
end
