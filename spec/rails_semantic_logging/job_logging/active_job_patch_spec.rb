RSpec.describe RailsSemanticLogging::JobLogging::ActiveJobPatch do
  describe 'TestJob' do
    it 'includes the ActiveJob patch' do
      expect(TestJob.ancestors).to include(described_class)
    end

    it 'logs with named tags when performed' do
      expect { TestJob.perform_now('hello') }.to log_semantic(
        level: :info,
        message: /Processing: hello/
      )
    end

    it 'tags logs with job_class' do
      expect { TestJob.perform_now('hello') }.to log_semantic(
        named_tags: { job_class: 'TestJob' }
      )
    end

    it 'tags logs with queue name' do
      expect { TestJob.perform_now('hello') }.to log_semantic(
        named_tags: { queue: 'default' }
      )
    end

    it 'tags logs with the execution count' do
      # perform_now leaves executions at 0; a queued execution would increment it.
      expect { TestJob.perform_now('hello') }.to log_semantic(
        named_tags: { executions: 0 }
      )
    end

    it 'tags logs with provider_job_id when the adapter provides one' do
      allow_any_instance_of(TestJob).to receive(:provider_job_id).and_return('sq-42')

      expect { TestJob.perform_now('hello') }.to log_semantic(
        named_tags: { provider_job_id: 'sq-42' }
      )
    end

    it 'omits provider_job_id when the adapter does not provide one' do
      # The :test adapter used by the dummy app does not assign a
      # provider_job_id, so the tag must be absent rather than nil.
      expect {
        TestJob.perform_now('hello')
      }.to(have_logged_message('Processing: hello').with_formatted_event do |event, _formatted|
        expect(event.named_tags).to include(job_class: 'TestJob')
        expect(event.named_tags).to_not have_key(:provider_job_id)
      end)
    end
  end
end
