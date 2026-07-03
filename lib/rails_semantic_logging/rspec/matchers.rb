require 'json'
require 'semantic_logger'
require_relative '../formatters/datadog'

module RailsSemanticLogging
  module RSpec
    # In-memory appender that collects log entries for assertion
    class InMemoryAppender < SemanticLogger::Subscriber
      attr_reader :logs

      def initialize
        super(level: :trace)
        @logs = []
      end

      def log(log_entry)
        @logs << log_entry
      end

      def flush
        # No-op for in-memory
      end
    end

    # Shared capture plumbing for the block matchers. Opens the logger gate to
    # :trace so every event reaches the in-memory capture appender, while
    # pinning the pre-existing appenders to the previously *visible* threshold
    # (default_level, or an active SemanticLogger.silence override such as the
    # LOG env var hook) so widening the gate does not spill every captured
    # event to stdout.
    module CaptureAppender
      module_function

      def with_capture_appender(capture)
        previous_level = ::SemanticLogger.default_level
        pinned = pin_live_appenders(visible_level(previous_level))
        ::SemanticLogger.add_appender(appender: capture)
        ::SemanticLogger.default_level = :trace
        yield
        ::SemanticLogger.flush
      ensure
        ::SemanticLogger.default_level = previous_level
        pinned&.each { |appender, level| appender.level = level }
        ::SemanticLogger.remove_appender(capture)
      end

      # Pins every live appender to +level+, returning the [appender, original_level]
      # pairs needed to restore them afterwards.
      def pin_live_appenders(level)
        ::SemanticLogger.appenders.to_a.map do |appender|
          original = appender.level
          appender.level = level
          [appender, original]
        end
      end

      # The threshold actually in effect before the matcher widened the gate:
      # a SemanticLogger.silence override (stored as a level index in a
      # thread-local by both semantic_logger 4.x and 5.x) wins over default_level.
      def visible_level(default_level)
        silence_index = Thread.current[:semantic_logger_silence]
        silence_index ? ::SemanticLogger::Levels::LEVELS[silence_index] : default_level
      end
    end

    # RSpec matcher for asserting log output from a block.
    #
    # Usage:
    #   expect { logger.info("hello") }.to log_semantic(level: :info, message: /hello/)
    #   expect { logger.warn("oops", payload: { key: "val" }) }.to log_semantic(payload: { key: "val" })
    class LogSemanticMatcher
      def initialize(expected)
        @expected_level = expected[:level]
        @expected_message = expected[:message]
        @expected_named_tags = expected[:named_tags]
        @expected_payload = expected[:payload]
        @captured_logs = []
      end

      def matches?(block)
        appender = InMemoryAppender.new
        CaptureAppender.with_capture_appender(appender) { block.call }

        @captured_logs = appender.logs
        @captured_logs.any? { |log| matches_log?(log) }
      end

      def supports_block_expectations?
        true
      end

      def failure_message
        "expected block to log a message matching #{expected_description}, but captured logs were:\n#{format_logs}"
      end

      def failure_message_when_negated
        "expected block not to log a message matching #{expected_description}, but it did"
      end

      private

      def matches_log?(log)
        matches_level?(log) && matches_message?(log) && matches_named_tags?(log) && matches_payload?(log)
      end

      def matches_level?(log)
        return true unless @expected_level

        log.level == @expected_level
      end

      def matches_message?(log)
        return true unless @expected_message

        case @expected_message
        when Regexp then @expected_message.match?(log.message.to_s)
        else log.message.to_s == @expected_message.to_s
        end
      end

      def matches_named_tags?(log)
        return true unless @expected_named_tags

        @expected_named_tags.all? { |key, value| log.named_tags[key] == value }
      end

      def matches_payload?(log)
        return true unless @expected_payload
        return false unless log.payload

        @expected_payload.all? { |key, value| log.payload[key] == value }
      end

      def expected_description
        parts = []
        parts << "level: #{@expected_level.inspect}" if @expected_level
        parts << "message: #{@expected_message.inspect}" if @expected_message
        parts << "named_tags: #{@expected_named_tags.inspect}" if @expected_named_tags
        parts << "payload: #{@expected_payload.inspect}" if @expected_payload
        "{#{parts.join(', ')}}"
      end

      def format_logs
        return '  (none)' if @captured_logs.empty?

        @captured_logs.map { |log| "  [#{log.level}] #{log.message} tags=#{log.named_tags} payload=#{log.payload}" }.join("\n")
      end
    end

    # Block matcher that finds a specific log event by message and exposes both
    # the raw SemanticLogger::Log and an optionally formatted version to a user
    # block, so the test can make arbitrary assertions on the event.
    #
    # Complementary to `log_semantic`:
    # * `log_semantic` is declarative ("was anything matching these criteria
    #   logged?") and returns a boolean.
    # * `have_logged_message` is imperative — it finds the event, hands it over
    #   to the test, and lets the test assert whatever it needs.
    #
    # Usage:
    #   expect { logger.info("hello", key: "val") }.to have_logged_message("hello")
    #   expect { do_work }.to have_logged_message(/import/, :warn)
    #
    #   expect { service.call }
    #     .to have_logged_message("Completed").with_formatted_event { |event, formatted|
    #       expect(event.payload).to include(order_id: order.id)
    #       expect(formatted.dig("http", "status_code")).to eq(200)
    #     }
    #
    # The optional `with_formatted_event` block receives `(event, formatted)`
    # where `formatted` is the JSON output of the chosen formatter parsed back
    # with indifferent access. By default the gem's Datadog formatter is used;
    # pass any `SemanticLogger::Formatters::Base` subclass to override:
    #
    #   .with_formatted_event(SemanticLogger::Formatters::Json) { |event, formatted| ... }
    class HaveLoggedMessageMatcher
      attr_reader :event_block

      DEFAULT_FORMATTER = ::RailsSemanticLogging::Formatters::Datadog

      def initialize(expected, expected_level = nil)
        @expected_message = expected
        @expected_level = expected_level
        @formatter_class = DEFAULT_FORMATTER
      end

      def matches?(block)
        # Capture the live appender BEFORE we attach our test appender. The
        # Datadog formatter reads `logger.host` on the appender it receives, so
        # the formatter call later on needs a real one (any subscriber will do).
        @live_appender = ::SemanticLogger.appenders.first
        @log_event = capture_first_matching_event(block)
        return false unless @log_event
        return false if @expected_level && @log_event.level != @expected_level

        @event_block&.call(@log_event, formatted)
        true
      rescue ::RSpec::Expectations::ExpectationNotMetError => e
        @error = e
        false
      end

      def supports_block_expectations?
        true
      end

      # Attach a block that receives the matched `(log_event, formatted)` pair.
      # `formatted` is the JSON output of the configured formatter, parsed back
      # with `HashWithIndifferentAccess` so callers can navigate the structure
      # with either string or symbol keys.
      def with_formatted_event(formatter_class = nil, &block)
        raise ArgumentError, 'block is required' unless block
        if formatter_class && !(formatter_class < ::SemanticLogger::Formatters::Base)
          raise ArgumentError,
                "formatter must inherit from SemanticLogger::Formatters::Base, got #{formatter_class.inspect}"
        end

        @formatter_class = formatter_class if formatter_class
        @event_block = block
        self
      end

      def failure_message
        return @error.message if @error
        if @log_event && @expected_level && @log_event.level != @expected_level
          return "expected log level #{@expected_level.inspect}, got #{@log_event.level.inspect}"
        end

        "expected block to log a message matching #{@expected_message.inspect}"
      end

      def failure_message_when_negated
        "expected block NOT to log a message matching #{@expected_message.inspect}, but a matching event was emitted"
      end

      private

      def capture_first_matching_event(block)
        capture = InMemoryAppender.new
        CaptureAppender.with_capture_appender(capture) { block.call }
        capture.logs.find { |evt| message_matches?(evt.message) }
      end

      # Matches String, Regex and any object that implements `===` (incl. RSpec
      # built-in matchers like `a_string_starting_with("...")`).
      def message_matches?(actual)
        @expected_message === actual.to_s # rubocop:disable Style/CaseEquality
      end

      # Format a *copy* of the log event so a buggy formatter that mutates
      # log.payload / log.named_tags cannot leak back into the event we hand
      # off to the user block.
      def formatted
        @formatted ||= begin
          safe_log = duped_log_event
          ::JSON.parse(@formatter_class.new.call(safe_log, @live_appender)).with_indifferent_access
        end
      end

      def duped_log_event
        copy = @log_event.dup
        copy.payload = @log_event.payload.dup if @log_event.payload.is_a?(::Hash)
        copy.named_tags = @log_event.named_tags.dup if @log_event.named_tags.is_a?(::Hash)
        copy.tags = @log_event.tags.dup if @log_event.tags.is_a?(::Array)
        copy
      end
    end

    module Matchers
      def log_semantic(expected = {})
        LogSemanticMatcher.new(expected)
      end

      def have_logged_message(expected, level = nil) # rubocop:disable Naming/PredicatePrefix
        HaveLoggedMessageMatcher.new(expected, level)
      end
    end
  end
end
