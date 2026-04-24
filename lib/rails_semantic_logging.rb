require_relative 'rails_semantic_logging/version'
require_relative 'rails_semantic_logging/configuration'
require_relative 'rails_semantic_logging/formatters/datadog'

module RailsSemanticLogging
  class Error < StandardError; end
end

require_relative 'rails_semantic_logging/railtie'
