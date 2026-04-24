RSpec.describe 'Controller logging' do
  describe 'GET /test' do
    it 'returns success' do
      get '/test'
      expect(response).to have_http_status(:ok)
    end

    it 'logs controller action' do
      expect {
        get '/test'
      }.to log_semantic(level: :info, message: /Test log from controller/)
    end

    it 'includes default log tags in request logs' do
      tags = Rails.application.config.log_tags
      expect(tags).to include(:request_id, :client_ip)
    end

    it 'logs completed request with status in payload' do
      expect {
        get '/test'
      }.to log_semantic(payload: { status: 200 })
    end

    it 'logs completed request with method in payload' do
      expect {
        get '/test'
      }.to log_semantic(payload: { method: 'GET' })
    end

    it 'logs completed request with path in payload' do
      expect {
        get '/test'
      }.to log_semantic(payload: { path: '/test' })
    end
  end
end
