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

    # Declaring appenders replaces the default file appender and the automatic
    # console stderr appender.
    it 'declares its own appenders' do
      expect(Rails.application.config.rails_semantic_logger.appenders?).to be true
    end

    it 'declares no extra server or console context appenders' do
      appenders = Rails.application.config.rails_semantic_logger.appenders
      expect(appenders.server).to be_empty
      expect(appenders.console).to be_empty
    end

    it 'includes request_id in log_tags' do
      expect(Rails.application.config.log_tags).to include(request_id: :request_id)
    end

    it 'includes client_ip in log_tags' do
      expect(Rails.application.config.log_tags).to include(client_ip: :remote_ip)
    end
  end
end
