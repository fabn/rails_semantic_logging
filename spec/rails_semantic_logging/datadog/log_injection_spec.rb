require 'rails_semantic_logging/datadog/log_injection'

RSpec.describe RailsSemanticLogging::Datadog::LogInjection do
  # Stand-ins for the Datadog modules the patch relies on. Mirrors the shape
  # that datadog 2.x's Patcher#inject_log_correlation expects, in particular
  # that LogInjection::PerformNowPatch is a real constant the Patcher can
  # `include` into ActiveJob::Base.
  let(:perform_now_patch) { Module.new { def perform_now = :original } }
  let(:logger_class) do
    Class.new do
      attr_reader :tagged_with

      def tagged(*tags)
        @tagged_with = tags
        yield
      end
    end
  end
  let(:log_injection) do
    Module.new.tap { |m| m.const_set(:PerformNowPatch, perform_now_patch) }
  end

  let(:fake_datadog) do
    correlation = Object.new
    def correlation.to_h = { dd: { trace_id: '123', span_id: '456' } }
    tracing_cfg = Object.new
    def tracing_cfg.log_injection? = true
    tracing_cfg.define_singleton_method(:log_injection) { true }
    config = Object.new
    config.define_singleton_method(:tracing) { tracing_cfg }

    tracing = Module.new
    tracing.define_singleton_method(:correlation) { correlation }
    tracing.const_set(:Contrib, Module.new)
    tracing::Contrib.const_set(:ActiveJob, Module.new)
    tracing::Contrib::ActiveJob.const_set(:LogInjection, log_injection)

    datadog = Module.new
    datadog.define_singleton_method(:configuration) { config }
    datadog.const_set(:Tracing, tracing)
    datadog
  end

  before { stub_const('::Datadog', fake_datadog) }

  describe '.apply!' do
    it 'preserves LogInjection::PerformNowPatch so Datadog Patcher can include it' do
      described_class.apply!
      expect(log_injection.const_defined?(:PerformNowPatch, false)).to be true
    end

    it 'redefines perform_now to tag the logger with hash correlation' do
      described_class.apply!
      instance = build_host(perform_now_patch).new
      instance.perform_now
      expect(instance.logger.tagged_with).to eq([{ dd: { trace_id: '123', span_id: '456' } }])
    end
  end

  def build_host(patch)
    cls = logger_class
    Class.new(Class.new { def perform_now = :original }) do
      include patch

      define_method(:logger) { @logger ||= cls.new }
    end
  end
end
