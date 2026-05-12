require "sidekiq/web"

index = ENV.fetch("SIDEKIQ_DB_INDEX", 12)

Sidekiq::Web.app_url = "/"

Sidekiq.configure_server do |config|
  redis_settings = {
    url: "#{ENV.fetch('REDIS_URL', nil)}/#{index}",
    password: ENV.fetch("REDIS_PASSWORD", nil),
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_NONE
    }
  }

  config.redis = redis_settings

  config.on(:startup) do
    schedule_file = "config/cron.yml"
    Sidekiq::Cron::Job.load_from_hash! YAML.load_file(schedule_file) if File.exist?(schedule_file)
  end
end

Sidekiq.configure_client do |config|
  redis_settings = {
    url: "#{ENV.fetch('REDIS_URL', nil)}/#{index}",
    password: ENV.fetch("REDIS_PASSWORD", nil),
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_NONE
    }
  }

  config.redis = redis_settings
end
