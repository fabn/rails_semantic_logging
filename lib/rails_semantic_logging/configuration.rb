require 'anyway_config'

module RailsSemanticLogging
  class Configuration < Anyway::Config
    config_name :rails_semantic_logging

    attr_config(
      application_name: nil,
      environment_name: nil,
      custom_log_tags: {},
      quiet_assets: true,
      sync_in_test: true,
      stdout_sync: true,
      default_payload: true,
      production_formatter: nil,
      development_formatter: :color
    )

    DEFAULT_LOG_TAGS = { request_id: :request_id, client_ip: :remote_ip }.freeze

    VALID_LOG_LEVELS = %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].freeze

    # Merges built-in default tags with app-provided custom tags
    def effective_log_tags
      DEFAULT_LOG_TAGS.merge(custom_log_tags)
    end

    # Returns the appropriate formatter for the given environment
    def formatter_for(env)
      case env.to_s
      when 'production'
        resolve_formatter(production_formatter) || RailsSemanticLogging::Formatters::Datadog.new
      else
        resolve_formatter(development_formatter) || :color
      end
    end

    # Returns the appropriate log level for the given environment, respecting LOG_LEVEL env var
    def log_level_for(env)
      default_level = case env.to_s
                      when 'development' then 'DEBUG'
                      when 'test' then 'FATAL'
                      else 'INFO'
                      end

      requested = ENV.fetch('LOG_LEVEL', default_level).to_s.upcase
      VALID_LOG_LEVELS.include?(requested) ? requested : default_level
    end

    private

    def resolve_formatter(value)
      value = value.to_sym if value.is_a?(String)
      return value unless value.is_a?(Symbol)
      return RailsSemanticLogging::Formatters::Datadog.new if value == :datadog

      value
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def reset_config!
      @config = Configuration.new
    end
  end
end
