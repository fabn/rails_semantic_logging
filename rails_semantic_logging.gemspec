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

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/fabn/rails_semantic_logging'
  spec.metadata['changelog_uri'] = 'https://github.com/fabn/rails_semantic_logging/releases'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'anyway_config', '>= 2.0'
  spec.add_dependency 'rails', '>= 7.0'
  spec.add_dependency 'rails_semantic_logger', '>= 4.0'
end
