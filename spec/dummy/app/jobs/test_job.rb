class ApplicationJob < ActiveJob::Base; end unless defined?(ApplicationJob)

class TestJob < ApplicationJob
  queue_as :default

  def perform(message)
    logger.info("Processing: #{message}")
  end
end
