require "active_support/core_ext/integer/time"

require "contextual_logger/formatters/color_formatter"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
  end

  config.cache_store = :memory_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local
  config.active_storage.variant_processor = :disabled

  routes.default_url_options[:host] = ENV["APP_URL"] || "http://localhost:3000"

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = {
    host: routes.default_url_options[:host]
  }

  config.action_mailer.delivery_method = :postmark
  config.action_mailer.postmark_settings = {
    api_token: Rails.application.credentials.dig(:postmark, :api_token)
  }

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Default activerecord encryption for ease of local dev
  config.active_record.encryption.primary_key =
    Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
    "JZcnPw4IvRp6P4pAbfCsENpAxbghOiPv"
  config.active_record.encryption.deterministic_key =
    Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
    "hIWebFlVbQ22cllX4ii1Qtq1UFe95KnA"
  config.active_record.encryption.key_derivation_salt =
    Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
    "EvBsq2idg2gdUs1NULVhV2ocWFdcKrzn"

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  config.assets.debug = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Enable the web console for local networks
  config.web_console.allowed_ips = %w[10.0.0.0/8 127.0.0.0/8 172.16.0.0/12 192.168.0.0/16 ::/64]

  config.log_level = ENV["LOG_LEVEL"]&.downcase&.strip&.to_sym || :debug
  SemanticLogger.add_appender(io: $stdout, formatter: ContextualLogger::Formatters::ColorFormatter.new)
end
