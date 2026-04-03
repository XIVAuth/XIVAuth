class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_observability_context, prepend: true

  before_action :redirect_to_new_domain

  helper PrideHelper

  def current_ability
    @current_ability ||= Abilities::UserAbility.new(current_user)
  end

  private def set_observability_context
    sentry_frontend_data = {
      environment: ENV["APP_ENV"] || Rails.env,
      dsn: Rails.application.credentials.dig(:sentry, :dsn, :frontend),
      user: { }
    }

    if user_signed_in?
      user_meta = { id: current_user.id, username: current_user.display_name }
      sentry_frontend_data[:user] = user_meta

      Sentry.set_user(user_meta)
      LogContext.add(user: user_meta)
    end

    gon.push({ app_env: ENV["APP_ENV"] || Rails.env })
    gon.push({ sentry: sentry_frontend_data })
  end

  private def redirect_to_new_domain
    if request.host == "edge.xivauth.net" || request.host == "www.xivauth.net"
      redirect_to "#{request.protocol}xivauth.net#{request.fullpath}", status: :moved_permanently, allow_other_host: true
    end

    if request.host == "eorzea.id"
      redirect_to "#{request.protocol}xivauth.net", status: :found, allow_other_host: true
    end
  end
end
