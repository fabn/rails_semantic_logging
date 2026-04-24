# Monkey patch for Datadog's ActiveJob LogInjection to use hash-style
# correlation tags instead of string-style. This is necessary because
# we patch ActiveJob::Logging to use named tags (job_class, job_id, queue),
# so Datadog must also use hash-style tags for compatibility with SemanticLogger.

module RailsSemanticLogging
  module Datadog
    module LogInjection
      def self.apply!
        return unless defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection)

        # Ensure the SemanticLogger ActiveJob extension is loaded first
        require 'rails_semantic_logger/extensions/active_job/logging'

        # Replace the original module with our patched version
        ::Datadog::Tracing::Contrib::ActiveJob.send(:remove_const, :LogInjection)
        ::Datadog::Tracing::Contrib::ActiveJob.const_set(:LogInjection, PatchedLogInjection)
      end

      # Replacement module that uses correlation.to_h instead of log_correlation
      module PatchedLogInjection
        def self.included(base)
          base.class_eval do
            around_perform do |_, block|
              if ::Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
                logger.tagged(::Datadog::Tracing.correlation.to_h, &block)
              else
                block.call
              end
            end
          end
        end
      end
    end
  end
end
