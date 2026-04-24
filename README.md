# RailsSemanticLogging

Opinionated Rails semantic logger configuration with Datadog support. Provides a consistent, structured JSON logging setup for Rails applications, with hooks for Sidekiq, ActiveJob, and Datadog-friendly formatters.

## Features

- **Datadog formatter** with [Standard Attributes](https://docs.datadoghq.com/standard-attributes/) mapping
- **Default payload enrichment** for controllers (host, user_agent, referer) mapped to `http.*`
- **JSON formatter** for structured logging without Datadog-specific fields
- **ActiveJob integration** with named tags (`job_class`, `job_id`, `queue`) instead of array tags
- **Sidekiq integration** with job context in all log lines
- **Configurable** via [anyway_config](https://github.com/palkan/anyway_config) (YAML, env vars, or code)
- **Environment-aware** defaults (Datadog JSON in production, color in development, fatal in test)
- **RSpec matcher** for asserting log output in tests

## Installation

Add to your application's Gemfile:

```ruby
gem 'rails_semantic_logging'
```

Then run `bundle install`.

## Usage

### Basic Configuration

The gem auto-configures via a Railtie when loaded by Rails. Out of the box:

- Datadog JSON formatter in production, color formatter elsewhere
- `request_id` and `client_ip` log tags
- Default payload enrichment (host, user_agent, referer) on all controller actions
- Quiet assets logging
- Sync mode in test environment
- Log level: INFO (production), DEBUG (development), FATAL (test)
- `LOG_LEVEL` env var override supported

### Custom Configuration

```ruby
# config/application.rb (inside class body)
RailsSemanticLogging.configure do |config|
  config.application_name = 'My App'
  config.environment_name = ENV.fetch('NAMESPACE', Rails.env)

  # Add custom log tags (merged with default request_id + client_ip)
  config.custom_log_tags = {
    user: ->(request) { extract_user_id(request) },
    tenant: ->(request) { request.headers['X-Tenant-ID'] }
  }

  # Override formatters (default: :datadog for production, :color for development)
  # config.production_formatter = :json     # plain JSON without Datadog mapping
  # config.production_formatter = :datadog  # Datadog Standard Attributes (default)
  # config.development_formatter = :color   # colorized console output (default)

  # Disable automatic payload enrichment on controllers (default: true)
  # config.default_payload = false
end
```

Configuration can also be set via YAML (`config/rails_semantic_logging.yml`) or environment variables (`RAILS_SEMANTIC_LOGGING_QUIET_ASSETS=false`) thanks to [anyway_config](https://github.com/palkan/anyway_config).

#### Formatter override via YAML

```yaml
# config/rails_semantic_logging.yml
production:
  production_formatter: json

development:
  development_formatter: color
```

#### Formatter override via environment variables

```bash
RAILS_SEMANTIC_LOGGING_PRODUCTION_FORMATTER=datadog bin/rails server
RAILS_SEMANTIC_LOGGING_DEVELOPMENT_FORMATTER=color bin/rails server
```

Both string and symbol values are accepted for formatter options (e.g. `"datadog"` from YAML/ENV is equivalent to `:datadog` in Ruby).

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `application_name` | Rails app name | SemanticLogger application name |
| `environment_name` | `Rails.env` | SemanticLogger environment name |
| `custom_log_tags` | `{}` | Extra log tags (merged with `request_id` + `client_ip`) |
| `quiet_assets` | `true` | Silence asset pipeline logs |
| `sync_in_test` | `true` | Use synchronous logging in test environment |
| `default_payload` | `true` | Auto-include host, user_agent, referer in controller logs |
| `production_formatter` | `:datadog` | Formatter for production (`:datadog`, `:json`, or instance) |
| `development_formatter` | `:color` | Formatter for non-production environments |

## Datadog Integration

### Standard Attributes Mapping

The `:datadog` formatter maps all log fields to [Datadog Standard Attributes](https://docs.datadoghq.com/standard-attributes/) so logs are automatically parsed and correlated in Datadog without custom pipelines.

#### Core log fields

| SemanticLogger field | Datadog Standard Attribute | Notes |
|---------------------|---------------------------|-------|
| Logger name | `logger.name` | Class/module that emitted the log |
| Level | `status` | `debug`, `info`, `warn`, `error`, `fatal` |
| Duration | `duration` | Converted to **nanoseconds** |
| Exception class | `error.kind` | e.g. `RuntimeError` |
| Exception message | `error.message` | Human-readable description |
| Backtrace | `error.stack` | Full stack trace as string |

#### HTTP fields (from controller payload)

When `default_payload` is enabled (default), controller request logs include:

| Payload field | Datadog Standard Attribute | Source |
|--------------|---------------------------|--------|
| `status` | `http.status_code` | Rails built-in |
| `method` | `http.method` | Rails built-in |
| `path` | `http.url` | Rails built-in |
| `host` | `http.url_details.host` | `DefaultPayload` concern |
| `user_agent` | `http.useragent` | `DefaultPayload` concern |
| `referer` | `http.referer` | `DefaultPayload` concern |

#### Datadog trace correlation

When Datadog tracing is active, the formatter injects: `dd.trace_id`, `dd.span_id`, `dd.env`, `dd.service`, `dd.version`.

### Example: Complete request log (production)

```json
{
  "timestamp": "2025-10-26T10:30:45.123Z",
  "status": "info",
  "host": "web-01",
  "logger.name": "Rails",
  "message": "Completed 200 OK in 42ms",
  "duration": 42500000,
  "http.status_code": 200,
  "http.method": "GET",
  "http.url": "/api/v1/bikes",
  "http.url_details.host": "api.example.com",
  "http.useragent": "Mozilla/5.0 (iPhone; iOS 17.0)",
  "http.referer": "https://app.example.com/dashboard",
  "dd.trace_id": "1234567890",
  "dd.span_id": "9876543210"
}
```

### Example: Background job log

```json
{
  "timestamp": "2025-10-26T10:31:00.456Z",
  "status": "info",
  "host": "worker-01",
  "logger.name": "Rails",
  "message": "Performing ImportBikesJob from Sidekiq(default)",
  "named_tags": {
    "job_class": "ImportBikesJob",
    "job_id": "abc-123",
    "queue": "default"
  }
}
```

### Example: Error log

```json
{
  "timestamp": "2025-10-26T10:32:15.789Z",
  "status": "error",
  "host": "web-01",
  "logger.name": "BikeService",
  "message": "Failed to import bike",
  "error.kind": "ActiveRecord::RecordInvalid",
  "error.message": "Validation failed: VIN is not unique",
  "error.stack": "app/services/bike_service.rb:42:in `import'\n..."
}
```

## Formatters

### JSON Formatter `:json`

Plain structured JSON without Datadog-specific field mapping. Useful for non-Datadog log pipelines.

```json
{
  "timestamp": "2025-10-26T10:30:45.123Z",
  "level": "info",
  "host": "server-1",
  "name": "Rails",
  "message": "Processing request",
  "duration_ms": 42.5
}
```

### Color Formatter `:color` (development default)

Uses the built-in `SemanticLogger::Formatters::Color` for human-readable development output.

## RSpec Matcher

Include the matcher module in your spec config:

```ruby
require 'rails_semantic_logging/rspec/matchers'

RSpec.configure do |config|
  config.include RailsSemanticLogging::RSpec::Matchers
end
```

Usage:

```ruby
expect { logger.info("hello") }.to log_semantic(level: :info, message: /hello/)
expect { logger.warn("oops", key: "val") }.to log_semantic(payload: { key: "val" })
expect { do_work }.to log_semantic(named_tags: { job_class: 'MyJob' })
```

## Puma Integration

When using Puma in clustered mode, reopen log appenders after forking:

```ruby
# config/puma.rb
if workers_number.positive?
  preload_app!

  before_worker_boot do
    SemanticLogger.reopen
  end
end
```

## Development

```bash
git clone https://github.com/fabn/rails_semantic_logging.git
cd rails_semantic_logging
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
