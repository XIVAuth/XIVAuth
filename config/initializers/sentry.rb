require "environment_info"

Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :dsn, :backend)
  config.breadcrumbs_logger = %i[active_support_logger sentry_logger http_logger]

  config.environment = EnvironmentInfo.environment.to_s.downcase
  config.release = EnvironmentInfo.commit_hash

  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.1

  config.enabled_patches += [:sidekiq_cron]

  config.enable_logs = true
end
