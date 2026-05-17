require "sidekiq/web"
require "sidekiq/throttled"
require "sidekiq/throttled/web"
require "sidekiq_unique_jobs/web"

index = ENV.fetch("SIDEKIQ_DB_INDEX", 12)

Sidekiq::Web.app_url = "/"

Sidekiq.configure_server do |config|
  config.redis = {
    url: "#{ENV.fetch('REDIS_URL', nil)}/#{index}",
    password: ENV.fetch("REDIS_PASSWORD", nil),
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_NONE
    }
  }

  config.on(:startup) do
    schedule_file = "config/cron.yml"
    Sidekiq::Cron::Job.load_from_hash! YAML.load_file(schedule_file) if File.exist?(schedule_file)
  end

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: "#{ENV.fetch('REDIS_URL', nil)}/#{index}",
    password: ENV.fetch("REDIS_PASSWORD", nil),
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_NONE
    }
  }

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end

Sidekiq.default_job_options = {
  # Provides support for ActiveJob and SidekiqUniqueJobs
  lock_args_method: ->(args) { [ args.first.except("job_id", "enqueued_at") ] },
}