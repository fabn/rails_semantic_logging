RSpec.describe RailsSemanticLogging::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'has nil application_name' do
      expect(config.application_name).to be_nil
    end

    it 'has nil environment_name' do
      expect(config.environment_name).to be_nil
    end

    it 'has empty custom_log_tags' do
      expect(config.custom_log_tags).to eq({})
    end

    it 'has quiet_assets enabled' do
      expect(config.quiet_assets).to be true
    end

    it 'has sync_in_test enabled' do
      expect(config.sync_in_test).to be true
    end

    it 'has :color as development_formatter' do
      expect(config.development_formatter).to eq(:color)
    end
  end

  describe '#effective_log_tags' do
    it 'includes default request_id and client_ip tags' do
      expect(config.effective_log_tags).to include(request_id: :request_id, client_ip: :remote_ip)
    end

    it 'merges custom tags with defaults' do
      config.custom_log_tags = { user: ->(r) { r } }
      tags = config.effective_log_tags
      expect(tags).to include(:request_id, :client_ip, :user)
    end

    it 'allows custom tags to override defaults' do
      config.custom_log_tags = { request_id: :custom }
      expect(config.effective_log_tags[:request_id]).to eq(:custom)
    end
  end

  describe '#formatter_for' do
    it 'returns Datadog formatter for production by default' do
      expect(config.formatter_for('production')).to be_a(RailsSemanticLogging::Formatters::Datadog)
    end

    it 'returns :color for development' do
      expect(config.formatter_for('development')).to eq(:color)
    end

    it 'returns :color for test' do
      expect(config.formatter_for('test')).to eq(:color)
    end

    it 'resolves :datadog symbol to Datadog formatter' do
      config.production_formatter = :datadog
      expect(config.formatter_for('production')).to be_a(RailsSemanticLogging::Formatters::Datadog)
    end

    it 'passes through unknown symbols' do
      config.production_formatter = :color
      expect(config.formatter_for('production')).to eq(:color)
    end

    context 'with string values from YAML or ENV' do
      it 'resolves "datadog" string to Datadog formatter' do
        config.production_formatter = 'datadog'
        expect(config.formatter_for('production')).to be_a(RailsSemanticLogging::Formatters::Datadog)
      end

      it 'resolves "color" string to :color symbol' do
        config.development_formatter = 'color'
        expect(config.formatter_for('development')).to eq(:color)
      end

      it 'resolves "json" string to :json symbol' do
        config.production_formatter = 'json'
        expect(config.formatter_for('production')).to eq(:json)
      end
    end
  end

  describe '#log_level_for' do
    it 'returns INFO for production' do
      expect(config.log_level_for('production')).to eq('INFO')
    end

    it 'returns DEBUG for development' do
      expect(config.log_level_for('development')).to eq('DEBUG')
    end

    it 'returns FATAL for test' do
      expect(config.log_level_for('test')).to eq('FATAL')
    end

    it 'respects LOG_LEVEL env var for production' do
      allow(ENV).to receive(:fetch).with('LOG_LEVEL', 'INFO').and_return('WARN')
      expect(config.log_level_for('production')).to eq('WARN')
    end

    it 'falls back to default for invalid LOG_LEVEL' do
      allow(ENV).to receive(:fetch).with('LOG_LEVEL', 'INFO').and_return('INVALID')
      expect(config.log_level_for('production')).to eq('INFO')
    end
  end

  describe '.configure' do
    after { RailsSemanticLogging.reset_config! }

    it 'yields the config' do
      RailsSemanticLogging.configure do |c|
        c.application_name = 'TestApp'
      end
      expect(RailsSemanticLogging.config.application_name).to eq('TestApp')
    end
  end
end
