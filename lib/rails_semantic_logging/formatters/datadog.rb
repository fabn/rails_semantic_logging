require 'semantic_logger'

module RailsSemanticLogging
  module Formatters
    # Datadog-optimized JSON formatter that maps log fields to
    # Datadog Standard Attributes (https://docs.datadoghq.com/standard-attributes/).
    #
    # Key mappings:
    #   name              -> logger.name
    #   level             -> status
    #   duration          -> duration (nanoseconds) + duration_human (Rails format)
    #   exception         -> error: { kind, message, stack }
    #   payload           -> http: { status_code, method, url, ... } (controller requests)
    #   named_tags.dd     -> dd (top-level, for trace linking)
    #   named_tags.user_* -> usr.{id, email, name, role}
    class Datadog < ::SemanticLogger::Formatters::Raw
      NANOSECONDS_PER_MILLISECOND = 1_000_000

      # Mapping of Rails payload keys to Datadog http standard attribute names
      HTTP_PAYLOAD_MAP = {
        status: :status_code,
        method: :method,
        host: :host,
        user_agent: :useragent,
        referer: :referer
      }.freeze

      # Mapping of user-related named_tags to usr.* standard attributes
      USER_NAMED_TAGS_MAP = {
        user_id: :id,
        user_email: :email,
        user_name: :name,
        user_role: :role
      }.freeze

      def initialize(time_format: :iso_8601, time_key: :timestamp, **args) # rubocop:disable Naming/VariableNumber
        super(time_format:, time_key:, log_application: false, log_host: true, log_environment: false, **args)
      end

      def call(log, logger)
        super
        remap_named_tags
        remap_http_payload
        parse_url_details
        apache_message
        deep_compact_blank!(hash)
        hash.to_json
      end

      def thread_name
        # Exclude thread_name from output
      end

      def name
        hash[:'logger.name'] = log.name if log.name
      end

      def level
        hash[:status] = log.level
      end

      def duration
        # Propagate duration from payload if not set on log
        log.duration = log.payload[:duration] if log.duration.nil? && log.payload&.dig(:duration)
        return unless log.duration

        # Datadog standard: duration in nanoseconds
        hash[:duration] = (log.duration * NANOSECONDS_PER_MILLISECOND).to_i
        # Human-readable duration for readability (Rails format)
        hash[:duration_human] = "#{log.duration.round(2)}ms"
      end

      def exception
        return unless log.exception

        hash[:error] = {
          kind: log.exception.class.name,
          message: log.exception.message,
          stack: log.exception.backtrace&.join("\n")
        }
      end

      private

      # Parses http.url into url_details with host, path and queryString
      def parse_url_details
        return unless hash.dig(:http, :url)

        url = hash[:http][:url]
        path, query = url.split('?', 2)
        details = { path: path }
        details[:queryString] = Rack::Utils.parse_query(query) if query.present?
        # Datadog standard: host belongs under http.url_details
        details[:host] = hash[:http].delete(:host) if hash[:http][:host]

        hash[:http][:url_details] = details
      end

      # For completed ActionController requests, replace the message with an
      # Apache-like format: "GET /path JSON 200 1.17ms" for better readability on mobile
      def apache_message
        return unless hash[:http].is_a?(Hash) && hash[:http][:status_code] && log.duration

        method = hash[:http][:method] || '-'
        url = hash[:http][:url] || '-'
        status = hash[:http][:status_code]
        format = hash[:payload].is_a?(Hash) ? hash[:payload][:format] : nil

        parts = [method, url]
        parts << format if format.present?
        parts << status
        parts << "#{log.duration.round(2)}ms"
        hash[:message] = parts.join(' ')
      end

      # Remaps known named_tags to Datadog standard attributes.
      # Handles: client_ip, request_id, dd correlation, user_* tags.
      def remap_named_tags
        return unless hash[:named_tags].is_a?(Hash)

        remap_network_and_request
        remap_dd_correlation
        remap_user_tags
      end

      def remap_network_and_request
        if (ip = hash[:named_tags].delete(:client_ip))
          hash[:network] = { client: { ip: ip } }
        end

        return unless (rid = hash[:named_tags].delete(:request_id))

        hash[:http] ||= {}
        hash[:http][:request_id] = rid
      end

      # Lifts Datadog correlation from named_tags (added by dd-trace-rb SemanticLogger
      # instrumentation via Tracing.correlation.to_h) to top-level for trace linking.
      # Skips the dd block entirely when there's no active trace (trace_id is "0").
      def remap_dd_correlation
        dd = hash[:named_tags].delete(:dd)
        ddsource = hash[:named_tags].delete(:ddsource)

        return unless dd.is_a?(Hash) && dd[:trace_id].to_s != '0'

        hash[:dd] = dd
        hash[:ddsource] = ddsource if ddsource
      end

      # Maps user_* named_tags to usr.* Datadog standard attributes
      def remap_user_tags
        usr = USER_NAMED_TAGS_MAP.each_with_object({}) do |(source, target), h|
          value = hash[:named_tags].delete(source)
          h[target] = value if value.present?
        end

        hash[:usr] = usr if usr.present?
      end

      # Remaps known HTTP payload fields to nested Datadog http standard attributes
      def remap_http_payload
        return unless hash[:payload].is_a?(Hash)

        http = HTTP_PAYLOAD_MAP.each_with_object({}) do |(source, target), h|
          h[target] = hash[:payload].delete(source) if hash[:payload].key?(source)
        end

        # Prefer full_path (with query string) over path (stripped by rails_semantic_logger).
        # Delete both keys unconditionally to avoid duplication in payload.
        full_path = hash[:payload].delete(:full_path)
        path = hash[:payload].delete(:path)
        url = full_path || path
        http[:url] = url if url.present?
        return if http.blank?

        hash[:http].is_a?(Hash) ? hash[:http].merge!(http) : hash[:http] = http
      end

      # Recursively removes blank values from a hash
      def deep_compact_blank!(h)
        h.each do |key, value|
          deep_compact_blank!(value) if value.is_a?(Hash)
          h.delete(key) if value.blank?
        end
        h
      end
    end
  end
end
