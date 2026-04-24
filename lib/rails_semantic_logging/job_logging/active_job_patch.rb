require 'active_support/concern'

module RailsSemanticLogging
  module JobLogging
    # ActiveJob patch to provide named tags instead of array tags.
    # Converts the default tag_logger(class, id) call into named tags
    # (job_class, job_id, queue) for structured logging.
    module ActiveJobPatch
      extend ActiveSupport::Concern

      def tag_logger(job_class = nil, job_id = nil, &)
        if job_class && job_id
          super(job_class: job_class, job_id: job_id, queue: queue_name, &)
        else
          super(&)
        end
      end
    end
  end
end
