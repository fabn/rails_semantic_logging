require 'json'

RSpec.describe RailsSemanticLogging::Formatters::Datadog do
  subject(:formatter) { described_class.new }

  let(:appender) { SemanticLogger.appenders.first }
  let(:log_entry) do
    SemanticLogger::Log.new('TestLogger', :info).tap do |log|
      log.message = 'Test message'
    end
  end

  describe 'Datadog Standard Attributes' do
    it 'maps name to logger.name' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['logger.name']).to eq('TestLogger')
      expect(parsed).to_not have_key('name')
    end

    it 'maps level to status' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['status']).to eq('info')
      expect(parsed).to_not have_key('level')
    end

    it 'includes host' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to have_key('host')
    end

    it 'includes message' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['message']).to eq('Test message')
    end

    it 'uses timestamp key' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to have_key('timestamp')
    end

    it 'excludes thread_name' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to_not have_key('thread_name')
    end

    it 'removes blank values from output' do
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.values).to_not include(nil, '', [])
    end
  end

  describe '#duration' do
    it 'converts duration to nanoseconds' do
      log_entry.duration = 42.5 # milliseconds
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['duration']).to eq(42_500_000)
    end

    it 'includes human-readable duration' do
      log_entry.duration = 42.5
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['duration_human']).to eq('42.5ms')
    end

    it 'propagates duration from payload' do
      log_entry.payload = { duration: 10.0 }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['duration']).to eq(10_000_000)
    end
  end

  describe '#exception' do
    it 'maps exception to nested error object' do
      error = RuntimeError.new('something went wrong')
      error.set_backtrace(%w[line1 line2])
      log_entry.exception = error

      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('error', 'kind')).to eq('RuntimeError')
      expect(parsed.dig('error', 'message')).to eq('something went wrong')
      expect(parsed.dig('error', 'stack')).to eq("line1\nline2")
    end
  end

  describe 'HTTP payload remapping' do
    it 'maps Rails payload to nested http object' do
      log_entry.payload = { status: 200, method: 'GET', path: '/api/test' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('http', 'status_code')).to eq(200)
      expect(parsed.dig('http', 'method')).to eq('GET')
      expect(parsed.dig('http', 'url')).to eq('/api/test')
    end

    it 'maps DefaultPayload fields to nested http object' do
      log_entry.payload = { full_path: '/test', host: 'api.example.com', user_agent: 'Mozilla/5.0', referer: 'https://example.com' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('http', 'url_details', 'host')).to eq('api.example.com')
      expect(parsed.dig('http', 'host')).to be_nil
      expect(parsed.dig('http', 'useragent')).to eq('Mozilla/5.0')
      expect(parsed.dig('http', 'referer')).to eq('https://example.com')
    end

    it 'removes remapped keys from payload and keeps custom fields' do
      log_entry.payload = { status: 200, custom_field: 'kept' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('http', 'status_code')).to eq(200)
      expect(parsed.dig('payload', 'custom_field')).to eq('kept')
    end

    it 'cleans up empty payload after remapping' do
      log_entry.payload = { status: 200 }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to_not have_key('payload')
    end
  end

  describe 'apache message' do
    it 'replaces message with apache-like format for completed requests' do
      log_entry.message = 'Completed #index'
      log_entry.duration = 42.5
      log_entry.payload = { status: 200, method: 'GET', path: '/api/bikes' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['message']).to eq('GET /api/bikes 200 42.5ms')
    end

    it 'includes format from payload when present' do
      log_entry.message = 'Completed #index'
      log_entry.duration = 42.5
      log_entry.payload = { status: 200, method: 'GET', path: '/api/bikes', format: 'JSON' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['message']).to eq('GET /api/bikes JSON 200 42.5ms')
    end

    it 'does not change message for non-request logs' do
      log_entry.message = 'Some other log'
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed['message']).to eq('Some other log')
    end
  end

  describe 'dd correlation' do
    it 'lifts dd from named_tags to top level' do
      log_entry.named_tags = { dd: { trace_id: 'abc123', span_id: 'def456' }, ddsource: 'ruby' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('dd', 'trace_id')).to eq('abc123')
      expect(parsed.dig('dd', 'span_id')).to eq('def456')
      expect(parsed['ddsource']).to eq('ruby')
    end

    it 'skips dd block when trace_id is "0" (no active trace)' do
      log_entry.named_tags = { dd: { trace_id: '0', span_id: '0' }, ddsource: 'ruby' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to_not have_key('dd')
      expect(parsed).to_not have_key('ddsource')
    end
  end

  describe 'user named_tags' do
    it 'maps user_id, user_email, user_name, user_role to usr.* attributes' do
      log_entry.named_tags = {
        user_id: 42,
        user_email: 'mario@example.com',
        user_name: 'Mario Rossi',
        user_role: 'admin'
      }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('usr', 'id')).to eq(42)
      expect(parsed.dig('usr', 'email')).to eq('mario@example.com')
      expect(parsed.dig('usr', 'name')).to eq('Mario Rossi')
      expect(parsed.dig('usr', 'role')).to eq('admin')
    end

    it 'omits usr block when no user tags present' do
      log_entry.named_tags = { other: 'tag' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed).to_not have_key('usr')
    end
  end

  describe 'request_id and client_ip remapping' do
    it 'lifts client_ip to network.client.ip' do
      log_entry.named_tags = { client_ip: '10.0.0.1' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('network', 'client', 'ip')).to eq('10.0.0.1')
    end

    it 'lifts request_id to http.request_id' do
      log_entry.named_tags = { request_id: 'abc-123' }
      parsed = JSON.parse(formatter.call(log_entry, appender))
      expect(parsed.dig('http', 'request_id')).to eq('abc-123')
    end
  end
end
