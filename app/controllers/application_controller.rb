class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_observability_context, prepend: true
  before_action :update_session_metadata, prepend: true

  helper PrideHelper

  def current_ability
    @current_ability ||= Abilities::UserAbility.new(current_user)
  end

  private def update_session_metadata
    return unless user_signed_in?

    auth_data = session[:auth_data] || { }
    auth_data.merge!(helpers.build_auth_data("current"))
    ua = request.user_agent&.force_encoding("UTF-8")&.scrub
    auth_data[:current_browser] = helpers.parse_user_agent(ua) if auth_data.dig(:current_browser, :user_agent) != ua

    session[:auth_data] = auth_data
  end

  private def set_observability_context
    sentry_frontend_data = {
      environment: ENV["APP_ENV"] || Rails.env,
      dsn: Rails.application.credentials.dig(:sentry, :dsn, :frontend),
      release: EnvironmentInfo.commit_hash,
      user: { }
    }

    if user_signed_in?
      user_meta = { id: current_user.id, username: current_user.display_name }
      sentry_frontend_data[:user] = user_meta

      Sentry.set_user(user_meta)
      LogContext.add(user: user_meta)
    end

    gon.push({
      app_env: ENV["APP_ENV"] || Rails.env,
      app_commit_hash: EnvironmentInfo.commit_hash,
      sentry: sentry_frontend_data
    }.compact)
  end
end
