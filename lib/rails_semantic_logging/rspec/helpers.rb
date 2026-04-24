module RailsSemanticLogging
  module RSpec
    # Test helpers for applications using RailsSemanticLogging.
    #
    # Provides standalone helpers that work with or without TestProf:
    # - LoggingHelpers: with_logging / with_ar_logging (uses SemanticLogger.silence)
    # - SilenceOutput: capture stdout in tests
    # - Appender validation (ensures single appender at trace level)
    # - LOG env var support (LOG=all or LOG=ar to enable logging in tests)
    #
    # Usage:
    #   require 'rails_semantic_logging/rspec/helpers'
    #   RailsSemanticLogging::RSpec::Helpers.install!
    #
    module Helpers
      # Standalone logging helpers using SemanticLogger.silence.
      # Works without TestProf. If TestProf is present, also patches
      # TestProf::Rails::LoggingHelpers for compatibility.
      module LoggingHelpers
        def with_logging(level = :trace, &)
          SemanticLogger.silence(level, &)
        end

        def with_ar_logging(level = :trace, &)
          SemanticLogger.appenders.first.filter = ->(log) { log.name == 'ActiveRecord' }
          SemanticLogger.silence(level, &)
        ensure
          SemanticLogger.appenders.first.filter = nil
        end
      end

      # Helper to silence stdout output in tests
      module SilenceOutput
        def silence_stdout
          original_stdout = $stdout
          $stdout = StringIO.new
          yield
        ensure
          $stdout = original_stdout
        end
      end

      class << self
        # Installs all test helpers into RSpec configuration.
        def install!
          configure_rspec!
          patch_test_prof!
        end

        private

        def configure_rspec! # rubocop:disable Metrics/MethodLength
          ::RSpec.configure do |config|
            # Make logging helpers available in all specs
            config.include LoggingHelpers

            # Validate appender configuration
            config.before(:suite) do
              if SemanticLogger.appenders.size != 1 || SemanticLogger.appenders.first.level != :trace
                raise 'Expected only one appender with trace level, ' \
                      "got #{SemanticLogger.appenders.size} with #{SemanticLogger.appenders.map(&:level)}"
              end
            end

            # Enable logging via LOG env var (LOG=all for all logs, LOG=ar for ActiveRecord only)
            config.around do |ex|
              next ex.call if ENV['LOG'].blank?

              level = ENV.fetch('LOG_LEVEL', 'trace').to_sym
              ENV['LOG'].casecmp('ar').zero? ? with_ar_logging(level, &ex) : with_logging(level, &ex)
            end
          end
        end

        # If TestProf is loaded, also patch its LoggingHelpers for compatibility
        def patch_test_prof!
          return unless defined?(TestProf::Rails::LoggingHelpers)

          TestProf::Rails::LoggingHelpers.prepend(LoggingHelpers)
        end
      end
    end
  end
end
