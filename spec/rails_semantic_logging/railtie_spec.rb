RSpec.describe RailsSemanticLogging::Railtie do
  describe 'after Rails initialization' do
    it 'sets SemanticLogger.application to configured name' do
      expect(SemanticLogger.application).to eq('DummyApp')
    end

    it 'sets SemanticLogger.environment to configured name' do
      expect(SemanticLogger.environment).to eq('test')
    end

    it 'configures exactly one appender' do
      expect(SemanticLogger.appenders.size).to eq(1)
    end

    it 'configures the appender at trace level' do
      expect(SemanticLogger.appenders.first.level).to eq(:trace)
    end

    it 'configures quiet_assets' do
      # Dummy app sets quiet_assets = false since it has no asset pipeline
      expect(Rails.application.config.rails_semantic_logger.quiet_assets).to be false
    end

    it 'disables console_logger' do
      expect(Rails.application.config.rails_semantic_logger.console_logger).to be false
    end

    it 'disables file_appender' do
      expect(Rails.application.config.rails_semantic_logger.add_file_appender).to be false
    end

    it 'includes request_id in log_tags' do
      expect(Rails.application.config.log_tags).to include(request_id: :request_id)
    end

    it 'includes client_ip in log_tags' do
      expect(Rails.application.config.log_tags).to include(client_ip: :remote_ip)
    end
  end
end
