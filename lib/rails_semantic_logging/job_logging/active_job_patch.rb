require 'active_support/concern'

module RailsSemanticLogging
  module JobLogging
    # ActiveJob patch to provide named tags instead of array tags.
    # Converts the default tag_logger(class, id) call into named tags
    # (job_class, job_id, queue, provider_job_id, executions) for
    # structured logging.
    #
    # `provider_job_id` is the queue backend's native id (e.g. the
    # solid_queue_jobs row id, or the Sidekiq jid) and lets a log line be
    # correlated with the job in Mission Control / the solid_queue_* tables.
    # It is only present once the job has been enqueued, so it is added
    # conditionally. `executions` is the ActiveJob attempt counter, which
    # makes retries visible in the logs.
    module ActiveJobPatch
      extend ActiveSupport::Concern

      def tag_logger(job_class = nil, job_id = nil, &)
        if job_class && job_id
          tags = { job_class: job_class, job_id: job_id, queue: queue_name, executions: executions }
          tags[:provider_job_id] = provider_job_id if provider_job_id
          super(**tags, &)
        else
          super(&)
        end
      end
    end
  end
end
