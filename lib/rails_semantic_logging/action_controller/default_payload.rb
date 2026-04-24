module RailsSemanticLogging
  module ActionController
    # Concern that enriches controller log payload with standard HTTP request fields.
    # Include in ApplicationController (or a base controller) to automatically add
    # host, user_agent, and referer to every request log line.
    #
    # These fields are then mapped to Datadog Standard Attributes by the Datadog formatter:
    #   host       -> http.url_details.host
    #   user_agent -> http.useragent
    #   referer    -> http.referer
    #   status     -> http.status_code  (already in Rails payload)
    #   method     -> http.method       (already in Rails payload)
    #   path       -> http.url          (already in Rails payload)
    module DefaultPayload
      extend ActiveSupport::Concern

      # @see https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/instrumentation.rb
      def append_info_to_payload(payload)
        super
        # Use :full_path because rails_semantic_logger strips query string from :path
        payload[:full_path] = request.fullpath
        payload[:host] = request.host
        payload[:user_agent] = request.user_agent
        payload[:referer] = request.referer if request.referer.present?
      end
    end
  end
end
