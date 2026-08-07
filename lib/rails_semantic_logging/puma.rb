# frozen_string_literal: true

require 'semantic_logger'

module RailsSemanticLogging
  # Routes Puma's own output through SemanticLogger so the boot banner and
  # lifecycle lines become structured events instead of raw text.
  #
  # Without this, Puma writes those lines straight to stdout. In a container
  # that means the log collector ingests one plain-text event per line, tagged
  # with whatever host it infers rather than the pod, and none of them carry
  # the attributes every other line in the app has.
  #
  # This cannot be wired from the Railtie: `custom_logger` lives on Puma's
  # configuration DSL, which only exists while `config/puma.rb` is evaluated.
  # By the time Rails boots, `Puma::Launcher` has already read the option
  # (launcher.rb applies `@options[:custom_logger]` in its constructor), and
  # the `Puma::LogWriter` in use is a fresh instance built by the Rack handler
  # rather than the reachable `Puma::LogWriter::DEFAULT` singleton. So the app
  # has to opt in explicitly:
  #
  #   # config/puma.rb
  #   require 'rails_semantic_logging/puma'
  #   RailsSemanticLogging::Puma.activate(self)
  #
  # Note this covers Puma's own output only. The three `=> Booting Puma` /
  # `=> Rails ... starting` / `=> Run bin/rails server --help` lines come from
  # `Rails::Command::ServerCommand#print_boot_information`, which writes to
  # `$stdout` through Thor's `say` with no logger in between, and cannot be
  # captured here.
  module Puma
    # Puma calls `custom_logger.write(str)` when the object responds to
    # `:write`, otherwise it writes the line to stdout itself.
    class Adapter
      def initialize(logger)
        @logger = logger
      end

      def write(str)
        message = str.to_s.chomp
        return if message.empty?

        # Under `puma -C config/puma.rb` the banner is emitted before Rails is
        # loaded, so the Railtie has not registered an appender yet and
        # SemanticLogger would drop the message with no output at all — worse
        # than the plain-text line we set out to replace. Fall back to stdout
        # until an appender exists. With `rails server` the app is loaded first
        # and this branch is never taken.
        if ::SemanticLogger.appenders.empty?
          $stdout.puts(message)
        else
          @logger.info(message)
        end
      rescue StandardError
        # Puma logs "- Gracefully stopping, waiting for requests to finish"
        # from inside its SIGTERM trap handler (Single#stop_blocked, reached
        # from Launcher#setup_signals). Ruby forbids Mutex#synchronize in a
        # trap context, and SemanticLogger reaches one — directly or through
        # the datadog gem's SemanticLogger instrumentation — which raises
        # ThreadError and aborts the shutdown. Since SIGTERM is how containers
        # are stopped, a log line must never be able to take the server down:
        # emit it plainly and carry on.
        $stdout.puts(message)
      end
    end

    module_function

    # @param puma_config [Puma::DSL] the `self` of `config/puma.rb`
    # @param logger_name [String] name the events are logged under
    # @return [Adapter, nil] the installed adapter, or nil when unsupported
    def activate(puma_config, logger_name: 'Puma')
      # `custom_logger` was added in Puma 6.2.0. Degrade quietly on older
      # versions rather than raising from a boot file.
      return unless puma_config.respond_to?(:custom_logger)

      Adapter.new(::SemanticLogger[logger_name]).tap do |adapter|
        puma_config.custom_logger(adapter)
      end
    end
  end
end
