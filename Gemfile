source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby ">= 4.0.0", "< 4.1"

# Rails.
gem "rails", "~> 8.1.0"

# Core systems
gem "pg", "~> 1.5"
gem "puma", "~> 7.0"
gem "redis", "~> 5.2"

# Platform-specific
gem "tzinfo-data", platforms: %i[windows jruby]

# Frontend/Pipeline things
gem "cssbundling-rails"
gem "jsbundling-rails"
gem "propshaft"
gem "stimulus-rails"
gem "turbo-rails"

# Asset management
gem "shrine", "~> 3.6"

# JSON API
gem "jbuilder"

# Performance
gem "bootsnap", require: false

# Mail Services
gem "postmark-rails", "~> 0.22.1"

# Internal Security
gem "rack-cors", "~> 3.0.0"

# Workers
gem "sidekiq", "~> 8.0"
gem "sidekiq-cron", "~> 2.3"
gem "sidekiq-throttled", "~> 2.0"
gem "sidekiq-unique-jobs", "~> 8.1"

# Authentication / Authorization
gem "cancancan", "~> 3.5"
gem "devise", "~> 5.0"
gem "devise_zxcvbn", "~> 6.0.0"

# Authn (MFA)
gem "devise-two-factor", "~> 6.1"
gem "rqrcode", "~> 3.2"
gem "webauthn", "~> 3.4.1"

# OAuth2 Providers
gem "omniauth-github", "~> 2.0"
gem "omniauth-oauth2", "~> 1.8"
gem "omniauth-steam", "~> 1.0"
gem "omniauth-twitch", "~> 1.2"

# Outbound OAuth2
gem "doorkeeper", "~> 5.9.0"
gem "doorkeeper-device_authorization_grant",
    github: "XIVAuth/doorkeeper-device_authorization_grant",
    ref: "f84062469900890461b1f03d9c37960236413321"

# Feature flags
gem "flipper", "~> 1.3"
gem "flipper-active_record", "~> 1.3"
gem "flipper-ui", "~> 1.3"

# Internal security
gem "jwt", "~> 3.0"
gem "jwt-eddsa", "~> 0.9"
gem "omniauth-rails_csrf_protection", "~> 2.0"
gem "rails_cloudflare_turnstile", "~> 0.4"

# CA certificates
gem 'certificate_authority', '~> 1.1'

# HTTP Requests
gem "faraday", "~> 2.9"

# Better logging
gem "rails_semantic_logger", "~> 4.17"

# Observability (Sentry) - temp for now
gem "sentry-rails", "~> 6.3"
gem "sentry-ruby", "~> 6.3"
gem "sentry-sidekiq", "~> 6.3"
gem "stackprof", "~> 0.2"

# Heroku dependencies
gem "rexml", "~> 3.4.2"

# Helpers
gem "pagy", "~> 43.0"

# FIXME(DEPS): Required dep for devise-zxcvbn, see https://github.com/bitzesty/devise_zxcvbn/issues/49.
gem 'ostruct', '~> 0.6.3'

group :production do
  # Handle Cloudflare IPs in our X-Forwarded-For chain
  gem "cloudflare-rails", "~> 7.0"
end

group :development, :test do
  gem "debug", platforms: %i[mri windows]

  gem "amazing_print"

  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.4"
  gem "rspec_junit_formatter", "~> 0.6", require: false
  gem "rspec-rails", "~> 8.0"
  gem 'simplecov', require: false
  gem 'simplecov-cobertura', require: false

  # Analysis tools
  gem "brakeman", require: false

  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

gem "gon", "~> 7.0"
