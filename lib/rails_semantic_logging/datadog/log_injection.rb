# Monkey patches Datadog's ActiveJob LogInjection to use hash-style
# correlation tags instead of string-style.
#
# Background: Datadog ships LogInjection sub-modules (PerformNowPatch for
# Rails 6+, EnqueuePatch for the singleton enqueue path) and patches
# ActiveJob::Base by `prepend`ing them. By default they call
# `Datadog::Tracing.log_correlation`, which returns a flat string
# ("dd.trace_id=... dd.span_id=...") and ends up under `event.tags`.
#
# Once we patch ActiveJob::Logging#tag_logger to emit named tags, we want
# Datadog correlation to land in `named_tags` too, so traces and logs
# correlate properly in the Datadog UI. We achieve that by re-defining
# `perform_now` and `enqueue` on Datadog's own patch modules to call
# `Datadog::Tracing.correlation.to_h` and pass the resulting hash to
# `logger.tagged`.
#
# Because Datadog prepends those modules into ActiveJob::Base, our
# re-definitions take effect on every method dispatch — independent of
# load order, as long as `apply!` runs before any job is executed.

module RailsSemanticLogging
  module Datadog
    module LogInjection
      def self.apply!
        return unless defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection)

        # Ensure the SemanticLogger ActiveJob extension is loaded before we
        # override Datadog's patches, so the named-tags `tag_logger` is in place.
        require 'rails_semantic_logger/extensions/active_job/logging'

        patch_perform_now
        patch_enqueue
      end

      def self.patch_perform_now
        return unless defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection::PerformNowPatch)

        ::Datadog::Tracing::Contrib::ActiveJob::LogInjection::PerformNowPatch.module_eval do
          define_method(:perform_now) do
            if ::Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
              logger.tagged(::Datadog::Tracing.correlation.to_h) { super() }
            else
              super()
            end
          end
        end
      end

      def self.patch_enqueue
        return unless defined?(::Datadog::Tracing::Contrib::ActiveJob::LogInjection::EnqueuePatch)

        ::Datadog::Tracing::Contrib::ActiveJob::LogInjection::EnqueuePatch.module_eval do
          define_method(:enqueue) do |*args, **kwargs, &block|
            if ::Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
              logger.tagged(::Datadog::Tracing.correlation.to_h) { super(*args, **kwargs, &block) }
            else
              super(*args, **kwargs, &block)
            end
          end
        end
      end
    end
  end
end
