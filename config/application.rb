require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/xivauth_session_store"

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.eager_load_paths << Rails.root.join("lib/contextual_logger/log_context")

    # don't log to file by default.
    config.rails_semantic_logger.add_file_appender = false

    config.action_controller.include_all_helpers = false

    # Better error pages
    config.exceptions_app = lambda { |env|
      ErrorsController.action(:show).call(env)
    }

    config.action_dispatch.rescue_responses["CanCan::AccessDenied"] = :unauthorized

    # heroku compat for now
    if ENV["APP_ENV"].present?
      Rails.application.config.credentials.content_path = Rails.root.join("config/credentials/#{ENV['APP_ENV']}.yml.enc")
    end

    config.generators do |generate|
      generate.orm :active_record, primary_key_type: :uuid
    end

    config.session_store XivAuthSessionStore,
      key: "_xivauth_session_v1",
      redis: {
        url:          "#{ENV.fetch('REDIS_URL', 'redis://localhost:6379')}/#{ENV.fetch('REDIS_SESSION_DB_INDEX', 2)}",
        password:     ENV.fetch("REDIS_PASSWORD", nil),
        expire_after: 7.days,
        ssl_params:   { verify_mode: OpenSSL::SSL::VERIFY_NONE }
      }
  end
end
