# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`rails_semantic_logging` is a Ruby gem that provides opinionated, structured JSON logging for Rails applications using [rails_semantic_logger](https://github.com/rocketjob/rails_semantic_logger). It auto-configures via a Railtie and includes a Datadog-optimized formatter that maps log fields to [Datadog Standard Attributes](https://docs.datadoghq.com/standard-attributes/).

## Commands

```bash
bundle exec rspec                        # Run full test suite
bundle exec rspec spec/path/to/spec.rb   # Run a single spec file
bundle exec rspec spec/path:42            # Run a specific example by line number
bundle exec rubocop                       # Lint
bundle exec rubocop -a                    # Lint with auto-correct
bundle exec rake                          # Run both rspec and rubocop (default task)
```

### Test Logging

Tests run with log level FATAL by default. To see log output during tests:

```bash
LOG=all bundle exec rspec spec/path.rb              # Show all logs
LOG=ar bundle exec rspec spec/path.rb               # Show only ActiveRecord logs
LOG=all LOG_LEVEL=debug bundle exec rspec spec/path  # Control log level
```

### CI Matrix

Tests run against Ruby 3.2/3.3/3.4 x Rails 7.1/7.2/8.0. Use `RAILS_VERSION` env var to pin Rails version locally:

```bash
RAILS_VERSION=7.1 bundle update rails && bundle exec rspec
```

## Architecture

### Configuration Flow

`RailsSemanticLogging::Configuration` (backed by `anyway_config`) -> `Railtie` initializers -> `rails_semantic_logger` engine.

The Railtie runs its initializer **before** `rails_semantic_logger`'s `:initialize_logger` to set formatter, log level, tags, and appenders before the upstream engine boots.

### Key Components

- **`Railtie`** (`lib/rails_semantic_logging/railtie.rb`) — Central wiring point. Configures `rails_semantic_logger`, injects `DefaultPayload` into controllers, patches ActiveJob/Sidekiq/Datadog via `ActiveSupport.on_load` and `after_initialize`.
- **`Formatters::Datadog`** (`lib/rails_semantic_logging/formatters/datadog.rb`) — Extends `SemanticLogger::Formatters::Raw`. Remaps named_tags (client_ip, request_id, dd.*, user_*) and HTTP payload fields to Datadog standard attribute paths. Generates Apache-style messages for completed requests.
- **`ActionController::DefaultPayload`** — Concern included in controllers via `on_load`. Enriches `append_info_to_payload` with `full_path`, `host`, `user_agent`, `referer`.
- **`JobLogging::ActiveJobPatch`** — Converts positional `tag_logger(class, id)` calls to named tags (`job_class`, `job_id`, `queue`).
- **`JobLogging::SidekiqPatch`** — Wraps `Sidekiq::JobLogger#call` with `SemanticLogger.tagged` since Sidekiq thread context is lost in SemanticLogger's formatting thread.
- **`Datadog::LogInjection`** — Monkey-patches `Datadog::Tracing::Contrib::ActiveJob::LogInjection` to use `correlation.to_h` (hash tags) instead of `log_correlation` (string tags) for compatibility with the named-tags approach.

### RSpec Helpers (for consuming apps)

- **`RSpec::Matchers#log_semantic`** — Block matcher using an in-memory appender. Matches on `level`, `message` (string or regex), `named_tags`, `payload`.
- **`RSpec::Helpers.install!`** — Installs `with_logging`/`with_ar_logging` helpers, validates single-appender-at-trace-level setup, enables `LOG` env var support.

### Documentation Lookup

Use context7 MCP as the preferred way to look up documentation for this project's dependencies. Always resolve the library ID first, then query docs with the full question.

| Gem | Context7 Library ID | Notes |
|-----|---------------------|-------|
| semantic_logger | `/websites/logger_rocketjob_io` | Formatters, appenders, named tags |
| rails_semantic_logger | `/reidmorrison/rails_semantic_logger` | Rails integration, config options |
| anyway_config | `/palkan/anyway_config` | Configuration DSL, YAML/env loading |
| Rails (guides) | `/websites/guides_rubyonrails` | Latest guides (edge) |
| Rails (guides v8.0) | `/websites/guides_rubyonrails_v8_0` | Version-pinned guides |
| Rails (API docs) | `/websites/api_rubyonrails` | Class/method reference (13k snippets) |
| Rails (source) | `/rails/rails` | Use with version: `v7.2.2.1`, `v8.0.4`, `v8.1.2` |
| rspec-rails | `/rspec/rspec-rails` | Request specs, matchers, generators |

### Test Setup

Tests use a Rails dummy app at `spec/dummy/`. The spec helper boots the dummy app, includes matchers, and installs helpers. The helpers enforce that exactly one appender exists at `:trace` level — if your Railtie changes break this invariant, the suite will fail before any specs run.
