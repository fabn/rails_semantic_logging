# Monkey patch for Datadog's ActiveJob LogInjection to use hash-style
# correlation tags instead of string-style. SemanticLogger.tagged only
# routes Hash arguments to named_tags — a String goes into positional tags,
# which hides dd.trace_id/dd.span_id from Datadog's standard-attribute
# mapping and breaks trace ↔ log correlation in job logs.
#
# We redefine the method on the upstream PerformNowPatch module in place
# rather than replacing the LogInjection constant, so
# Datadog::Tracing::Contrib::ActiveJob::Patcher#inject_log_correlation
# (which references LogInjection::PerformNowPatch by name) keeps working.

module RailsSemanticLogging
  module Datadog
    module LogInjection
      def self.apply!
        return unless defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection)

        require 'rails_semantic_logger/extensions/active_job/logging'

        upstream = ::Datadog::Tracing::Contrib::ActiveJob::LogInjection
        return unless upstream.const_defined?(:PerformNowPatch, false)

        patch_perform_now(upstream::PerformNowPatch)
      end

      def self.patch_perform_now(mod)
        mod.module_eval do
          remove_method(:perform_now) if method_defined?(:perform_now, false)

          define_method(:perform_now) do
            if ::Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
              logger.tagged(::Datadog::Tracing.correlation.to_h) { super() }
            else
              super()
            end
          end
        end
      end
    end
  end
end
