require "environment_info"
require "sentry_ignorable"

Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :dsn, :backend)
  config.breadcrumbs_logger = %i[active_support_logger sentry_logger http_logger]

  config.sdk_logger = SemanticLogger[Sentry]

  config.environment = EnvironmentInfo.environment.to_s.downcase
  config.release = EnvironmentInfo.commit_hash

  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.1

  config.enabled_patches += [:sidekiq_cron]

  config.before_send = lambda do |event, hint|
    exception = hint&.dig(:exception)
    return event if exception.nil?
    return nil if exception.is_a?(SentryIgnorable)

    # Drop the SDK's own failures (transport/connection errors, rejected or oversized envelopes, etc.), even if they
    # were wrapped by something else on the way up.
    while exception
      return nil if exception.is_a?(Sentry::Error)
      exception = exception.cause
    end

    event
  end
end
