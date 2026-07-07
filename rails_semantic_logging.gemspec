require_relative 'lib/rails_semantic_logging/version'

Gem::Specification.new do |spec|
  spec.name = 'rails_semantic_logging'
  spec.version = RailsSemanticLogging::VERSION
  spec.authors = ['Fabio Napoleoni']
  spec.email = ['f.napoleoni@gmail.com']
  spec.license = 'MIT'

  spec.summary = 'Opinionated Rails semantic logger configuration with Datadog support'
  spec.description = 'Provides a consistent, opinionated setup for structured JSON logging in Rails, ' \
                     'with specific hooks for Sidekiq, ActiveJob, and Puma, as well as Datadog-friendly formatters.'
  spec.homepage = 'https://github.com/fabn/rails_semantic_logging'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = 'https://github.com/fabn/rails_semantic_logging/releases'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'VERSION', 'README.md', 'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'anyway_config', '~> 2.0'
  spec.add_dependency 'rails', '>= 7.1', '< 9'
  # 4.18.0 is the first release with the Sidekiq ERROR_HANDLER fix
  # (https://github.com/reidmorrison/rails_semantic_logger/pull/265): earlier
  # versions crash with "undefined method 'logger' for module
  # RailsSemanticLogger::Sidekiq" when handling errors without a job context.
  spec.add_dependency 'rails_semantic_logger', '>= 4.18', '< 6'
end
