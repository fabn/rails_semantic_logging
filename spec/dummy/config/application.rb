require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'rails_semantic_logger'
require 'rails_semantic_logging'

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path('..', __dir__)
    config.load_defaults 7.1
    config.eager_load = false
    config.active_job.queue_adapter = :test

    RailsSemanticLogging.configure do |c|
      c.application_name = 'DummyApp'
      c.environment_name = 'test'
      c.quiet_assets = false # No asset pipeline in dummy app
    end
  end
end
