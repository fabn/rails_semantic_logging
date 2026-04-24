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
  end
end
