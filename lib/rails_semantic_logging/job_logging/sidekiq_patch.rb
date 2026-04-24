module RailsSemanticLogging
  module JobLogging
    # Sidekiq patch to provide job context in every processed job log line.
    # SemanticLogger uses its own thread for formatting, so Sidekiq::Context
    # (stored in Thread.current) is lost. This patch wraps each job with
    # SemanticLogger named tags for consistent structured output.
    module SidekiqPatch
      # @param [Hash] item Sidekiq job hash
      # @param [String] queue Queue name
      def call(item, queue)
        Sidekiq.logger.tagged(job_class: item['class'], job_id: item['jid'], queue: queue) do
          super(item, queue)
        end
      end
    end
  end
end
