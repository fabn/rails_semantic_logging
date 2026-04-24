RSpec.describe RailsSemanticLogging::RSpec::Matchers do
  let(:logger) { SemanticLogger['MatcherTest'] }

  describe '#log_semantic' do
    it 'matches a log entry by level' do
      expect { logger.info('test') }.to log_semantic(level: :info)
    end

    it 'matches a log entry by exact message' do
      expect { logger.info('exact match') }.to log_semantic(message: 'exact match')
    end

    it 'matches a log entry by regexp message' do
      expect { logger.info('hello world') }.to log_semantic(message: /hello/)
    end

    it 'matches a log entry by level and message' do
      expect { logger.warn('careful') }.to log_semantic(level: :warn, message: 'careful')
    end

    it 'does not match wrong level' do
      expect { logger.info('test') }.to_not log_semantic(level: :error)
    end

    it 'does not match wrong message' do
      expect { logger.info('hello') }.to_not log_semantic(message: 'goodbye')
    end

    it 'matches when no criteria given (any log)' do
      expect { logger.info('anything') }.to log_semantic
    end

    it 'does not match when nothing is logged' do
      expect { nil }.to_not log_semantic(level: :info)
    end

    it 'matches a log entry by payload' do
      expect { logger.info('with data', key: 'value') }.to log_semantic(payload: { key: 'value' })
    end
  end
end
