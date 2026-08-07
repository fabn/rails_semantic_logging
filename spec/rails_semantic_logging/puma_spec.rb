# frozen_string_literal: true

require 'spec_helper'
require 'rails_semantic_logging/puma'
require 'puma'
require 'puma/dsl'
require 'puma/log_writer'

RSpec.describe RailsSemanticLogging::Puma do
  describe '.activate' do
    let(:puma_config) { instance_double(Puma::DSL, custom_logger: nil) }

    it 'installs an adapter as Puma custom_logger' do
      described_class.activate(puma_config)
      expect(puma_config).to have_received(:custom_logger).with(described_class::Adapter)
    end

    it 'returns the installed adapter' do
      expect(described_class.activate(puma_config)).to be_a(described_class::Adapter)
    end

    it 'names the logger Puma by default' do
      adapter = described_class.activate(puma_config)
      expect { adapter.write('hello') }.to(logged_under('Puma'))
    end

    it 'accepts a custom logger name' do
      adapter = described_class.activate(puma_config, logger_name: 'Web')
      expect { adapter.write('hello') }.to(logged_under('Web'))
    end

    def logged_under(name)
      have_logged_message('hello').with_formatted_event { |event, _formatted| expect(event.name).to eq(name) }
    end

    # Puma < 6.2.0 has no custom_logger. config/puma.rb is a boot file, so
    # raising there would take the process down.
    context 'when the Puma version has no custom_logger' do
      let(:old_puma_config) { Object.new }

      it 'does nothing and returns nil' do
        expect(described_class.activate(old_puma_config)).to be_nil
      end
    end
  end

  describe RailsSemanticLogging::Puma::Adapter do
    subject(:adapter) { described_class.new(SemanticLogger['Puma']) }

    it 'logs the line, stripping the trailing newline Puma may add' do
      expect { adapter.write("Puma starting in single mode...\n") }
        .to log_semantic(level: :info, message: 'Puma starting in single mode...')
    end

    it 'ignores blank lines' do
      expect { adapter.write("\n") }.to_not log_semantic(level: :info)
    end

    # `puma -C config/puma.rb`: the banner is written before Rails boots, so no
    # appender exists yet and SemanticLogger would swallow the message.
    context 'when no appender is registered yet' do
      before { allow(SemanticLogger).to receive(:appenders).and_return([]) }

      it 'falls back to stdout so the line is never lost' do
        expect { adapter.write('* Listening on http://0.0.0.0:3000') }
          .to output("* Listening on http://0.0.0.0:3000\n").to_stdout
      end
    end

    # Puma logs the graceful-stop line from inside its SIGTERM trap handler,
    # where Ruby forbids Mutex#synchronize — which SemanticLogger reaches. A
    # log line must never be able to abort a shutdown.
    context 'when the logger raises, as it does in a trap context' do
      subject(:adapter) { described_class.new(logger) }

      let(:logger) { instance_double(SemanticLogger::Logger) }

      before do
        allow(logger).to receive(:info).and_raise(ThreadError, "can't be called from trap context")
      end

      it 'does not propagate the error' do
        expect { adapter.write('- Gracefully stopping') }.to_not raise_error
      end

      it 'still emits the line on stdout' do
        expect { adapter.write('- Gracefully stopping') }
          .to output("- Gracefully stopping\n").to_stdout
      end
    end
  end

  # Drives the real collaborator rather than the adapter alone: what matters is
  # that Puma's own `log` path reaches SemanticLogger under the right name.
  describe 'end to end through Puma::LogWriter' do
    let(:stdout) { StringIO.new }
    let(:log_writer) do
      Puma::LogWriter.new(stdout, StringIO.new).tap do |writer|
        writer.custom_logger = described_class::Adapter.new(SemanticLogger['Puma'])
      end
    end

    it 'logs the line under the Puma logger name' do
      matcher = have_logged_message('* Listening on http://0.0.0.0:3000')
                .with_formatted_event { |event, _formatted| expect(event.name).to eq('Puma') }

      expect { log_writer.log('* Listening on http://0.0.0.0:3000') }.to(matcher)
    end

    it 'stops writing to stdout' do
      log_writer.log('* Listening on http://0.0.0.0:3000')
      expect(stdout.string).to be_empty
    end
  end
end
