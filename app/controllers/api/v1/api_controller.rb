class Api::V1::ApiController < ActionController::API
  # There are no "open" API calls; everything must require at least authorization.
  before_action :doorkeeper_authorize!

  rescue_from CanCan::AccessDenied do
    render json: { error: "Forbidden" }, status: :forbidden
  end
  before_action :load_token
  before_action :set_observability_context

  respond_to :json

  def current_user
    return unless doorkeeper_token[:resource_owner_type] == "User"
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: doorkeeper_token[:resource_owner_id])
  end

  def current_client_app
    @current_client_app ||= doorkeeper_token.application.application
  end

  def current_ability
    return @current_ability if defined?(@current_ability)

    @current_ability = Abilities::ClientAppAbility.new(current_client_app)
    return @current_ability if @current_user.blank?

    @current_ability = @current_ability.merge(Abilities::UserAbility.new(current_user))
  end

  private def check_resource_owner_presence
    render status: :unauthorized unless current_user.present? && current_user.persisted?
  end

  private def load_token
    @doorkeeper_token = doorkeeper_token
  end

  private def set_observability_context
    return unless doorkeeper_token

    ctx = {
      client_id: doorkeeper_token.application_id,
      scopes: doorkeeper_token.scopes
    }

    if current_user.present?
      Sentry.set_user(id: current_user.id, username: current_user.display_name)
      LogContext.add(user: { id: current_user.id, username: current_user.display_name })
    end

    Sentry.set_context("oauth_application", ctx)
    LogContext.add(oauth_application: ctx)
  end
end
