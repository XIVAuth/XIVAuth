require "environment_info"
require "sentry_ignorable"

ENV["OTEL_TRACES_SAMPLER"] ||= "parentbased_traceidratio"
ENV["OTEL_TRACES_SAMPLER_ARG"] ||= "0.1"

ENV["OTEL_TRACES_EXPORTER"] ||= ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? ? "otlp" : "none"
ENV["OTEL_LOGS_EXPORTER"] ||= "none"

sentry_dsn = Rails.application.credentials.dig(:sentry, :dsn, :backend)

OpenTelemetry::SDK.configure do |c|
  c.logger = SemanticLogger[OpenTelemetry]
  # service.name is the role (Railway sets "web"/"worker"); service.namespace makes it unique across apps.
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME") { Sidekiq.server? ? "worker" : "web" }
  service_version = ENV["OTEL_SERVICE_VERSION"].presence || EnvironmentInfo.commit_hash
  c.service_version = service_version if service_version.present?
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    "service.namespace" => "xivauth",
    "service.instance.id" => ENV["RAILWAY_REPLICA_ID"].presence || Socket.gethostname,
    "deployment.environment.name" => EnvironmentInfo.environment.to_s.downcase
  })
  c.use_all

  if sentry_dsn.present?
    dsn = Sentry::DSN.new(sentry_dsn)
    exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
      endpoint: "#{dsn.server}#{dsn.path}/api/#{dsn.project_id}/integration/otlp/v1/logs/",
      headers: { "X-Sentry-Auth" => dsn.generate_auth_header(client: "xivauth.otlp-logs") }
    )
    c.add_log_record_processor(OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter))
  end
end

Sentry.init do |config|
  config.dsn = sentry_dsn
  config.breadcrumbs_logger = %i[active_support_logger sentry_logger http_logger]

  config.sdk_logger = SemanticLogger[Sentry]

  config.environment = EnvironmentInfo.environment.to_s.downcase
  config.release = EnvironmentInfo.commit_hash

  config.otlp.enabled = true
  config.otlp.setup_otlp_traces_exporter = true

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
