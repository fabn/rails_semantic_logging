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

  describe '#have_logged_message' do
    it 'matches an exact message' do
      expect { logger.info('hello') }.to have_logged_message('hello')
    end

    it 'matches a regex message' do
      expect { logger.info('hello world') }.to have_logged_message(/hello/)
    end

    it 'matches when message uses an RSpec matcher (e.g. a_string_starting_with)' do
      expect { logger.info('Processing import') }.to have_logged_message(a_string_starting_with('Processing'))
    end

    it 'enforces the optional level argument' do
      expect { logger.warn('careful') }.to have_logged_message('careful', :warn)
      expect { logger.info('careful') }.to_not have_logged_message('careful', :warn)
    end

    it 'does not match when nothing is logged' do
      expect { nil }.to_not have_logged_message('anything')
    end

    it 'does not match when no log line matches the expected message' do
      expect { logger.info('hello') }.to_not have_logged_message('goodbye')
    end

    describe '.with_formatted_event' do
      # The braces on `with_formatted_event { ... }` are intentional: a `do/end`
      # would bind to `.to` instead of `.with_formatted_event` (precedence).
      # rubocop:disable Lint/AmbiguousBlockAssociation
      # Simulates the legacy mutate-and-strip behaviour: delete keys from
      # log.payload while building the output. The matcher must shield the
      # log event we yield to the block from those mutations.
      let(:mutating_formatter) do
        Class.new(SemanticLogger::Formatters::Raw) do
          def call(log, appender)
            super
            hash[:payload].delete(:bot) if hash[:payload].is_a?(Hash)
            hash.to_json
          end
        end
      end

      it 'yields the raw SemanticLogger::Log and a parsed JSON hash with indifferent access', :aggregate_failures do
        expect {
          logger.info('Processed feed', feed: 'amazon', tenant: 'eu')
        }.to have_logged_message('Processed feed').with_formatted_event { |event, formatted|
          expect(event).to be_a(SemanticLogger::Log)
          expect(event.payload[:feed]).to eq('amazon')
          expect(formatted[:status]).to eq('info')
          expect(formatted['logger.name']).to eq('MatcherTest')
          expect(formatted.dig('payload', 'tenant')).to eq('eu')
        }
      end

      it 'does not mutate the original log event when the formatter is buggy' do
        expect {
          logger.info('completed', bot: false, cart_id: 42)
        }.to have_logged_message('completed').with_formatted_event(mutating_formatter) { |event, _formatted|
          expect(event.payload).to include(bot: false, cart_id: 42)
        }
      end

      it 'accepts an alternate formatter class' do
        expect {
          logger.info('hi')
        }.to have_logged_message('hi').with_formatted_event(SemanticLogger::Formatters::Json) { |_event, formatted|
          # Default JSON formatter exposes :level, not :status.
          expect(formatted[:level]).to eq('info')
        }
      end
      # rubocop:enable Lint/AmbiguousBlockAssociation

      it 'rejects formatter classes that are not SemanticLogger formatters' do
        expect { have_logged_message('x').with_formatted_event(String) { 'noop' } }
          .to raise_error(ArgumentError, /SemanticLogger::Formatters::Base/)
      end

      it 'requires a block' do
        expect { have_logged_message('x').with_formatted_event }.to raise_error(ArgumentError, /block is required/)
      end

      it 'surfaces user-block expectation failures as match failures', :aggregate_failures do
        matcher = have_logged_message('hello').with_formatted_event do |_event, _formatted|
          raise RSpec::Expectations::ExpectationNotMetError, 'user block said no'
        end
        expect(matcher.matches?(-> { logger.info('hello') })).to be(false)
        expect(matcher.failure_message).to eq('user block said no')
      end
    end
  end
end
