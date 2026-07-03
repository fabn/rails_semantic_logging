RSpec.describe RailsSemanticLogging::RSpec::Helpers do
  describe 'appender validation' do
    it 'passes with single appender at trace level' do
      expect(SemanticLogger.appenders.size).to eq(1)
      expect(SemanticLogger.appenders.first.level).to eq(:trace)
    end
  end

  describe 'LoggingHelpers' do
    # LoggingHelpers is included globally by install!, so methods are available directly

    it 'provides with_logging method' do
      expect(self).to respond_to(:with_logging)
    end

    it 'provides with_ar_logging method' do
      expect(self).to respond_to(:with_ar_logging)
    end

    it 'with_logging enables log output at given level' do
      logger = SemanticLogger['HelpersTest']
      expect { with_logging(:info) { logger.info('test message') } }
        .to log_semantic(level: :info, message: 'test message')
    end

    it 'with_logging suppresses logs below the given level' do
      logger = SemanticLogger['HelpersTest']
      expect { with_logging(:warn) { logger.info('below threshold') } }
        .to_not log_semantic(message: 'below threshold')
    end
  end

  describe 'SilenceOutput' do
    include described_class::SilenceOutput

    it 'redirects stdout during block' do
      original = $stdout
      silence_stdout { expect($stdout).to_not equal(original) }
    end

    it 'restores stdout after block' do
      original = $stdout
      silence_stdout { $stdout.write('test') } # rubocop:disable RSpec/Output
      expect($stdout).to equal(original)
    end
  end
end
