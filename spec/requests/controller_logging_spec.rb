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

  describe 'unmatched route (ActionController::RoutingError)' do
    # rails_semantic_logger patches ActionDispatch::DebugExceptions to log the
    # real exception object, so an unmatched route reaches the formatter as a
    # genuine ActionController::RoutingError carrying Rails' standard
    # "No route matches [GET] \"/path\"" message. The Datadog formatter parses
    # that message into http.method and http.url_details.path so the log stays
    # correlated with the request in Datadog without a server-side grok parser.
    #
    # The exception is logged on its own (no log message), so we match the
    # blank-message error event and assert on the formatted Datadog payload.
    # rubocop:disable Lint/AmbiguousBlockAssociation
    it 'returns 404 for an unmatched route' do
      get '/does/not/exist'
      expect(response).to have_http_status(:not_found)
    end

    it 'enriches the routing error log with http.method and http.url_details.path', :aggregate_failures do
      expect {
        get '/products/123/missing'
      }.to have_logged_message(/\A\z/, :error).with_formatted_event { |event, formatted|
        expect(event.exception).to be_a(ActionController::RoutingError)
        expect(formatted.dig('error', 'kind')).to eq('ActionController::RoutingError')
        expect(formatted.dig('error', 'message')).to eq('No route matches [GET] "/products/123/missing"')
        # message falls back to the exception message instead of staying empty
        expect(formatted['message']).to eq('No route matches [GET] "/products/123/missing"')
        expect(formatted.dig('http', 'method')).to eq('GET')
        expect(formatted.dig('http', 'status_code')).to eq(404)
        expect(formatted.dig('http', 'url_details', 'path')).to eq('/products/123/missing')
      }
    end

    it 'extracts the HTTP verb for non-GET unmatched routes', :aggregate_failures do
      expect {
        post '/orders/sync'
      }.to have_logged_message(/\A\z/, :error).with_formatted_event { |_event, formatted|
        expect(formatted.dig('http', 'method')).to eq('POST')
        expect(formatted.dig('http', 'url_details', 'path')).to eq('/orders/sync')
      }
    end
    # rubocop:enable Lint/AmbiguousBlockAssociation
  end
end
