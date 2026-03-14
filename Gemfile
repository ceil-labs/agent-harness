source "https://rubygems.org"
ruby ">= 4.0.0"

# Core async runtime
gem "async", "~> 2.0"
gem "async-http", "~> 0.60"
gem "falcon", "~> 0.45"

# Telegram integration
gem "telegram-bot-ruby", "~> 2.0"

# Configuration
gem "dry-configurable", "~> 1.0"
gem "dry-validation", "~> 1.0"

# Observability
gem "prometheus-client", "~> 4.0"

# JSON processing
gem "oj", "~> 3.16"

# CLI
gem "thor", "~> 1.3"

group :development, :test do
  gem "minitest", "~> 5.25"
  gem "rake", "~> 13.0"
  gem "standard", "~> 1.0"  # Ruby linter/formatter
  gem "bundler-audit", "~> 0.9"  # Security audit for gems
  gem "webmock", "~> 3.25"  # HTTP request stubbing for tests
  gem "vcr", "~> 6.3"  # Record/replay HTTP interactions
end
