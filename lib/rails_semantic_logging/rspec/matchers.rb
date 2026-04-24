require 'semantic_logger'

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
        SemanticLogger.add_appender(appender: appender)
        # Temporarily lower log level to capture all messages
        previous_level = SemanticLogger.default_level
        SemanticLogger.default_level = :trace
        block.call
        SemanticLogger.flush
        SemanticLogger.default_level = previous_level
        SemanticLogger.remove_appender(appender)

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

    module Matchers
      def log_semantic(expected = {})
        LogSemanticMatcher.new(expected)
      end
    end
  end
end
