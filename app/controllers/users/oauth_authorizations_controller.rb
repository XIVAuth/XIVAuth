class Users::OAuthAuthorizationsController < ApplicationController
  layout "chroma/container"
  include Pagy::Method

  def index
    @pagy, @authorizations = pagy(current_user.oauth_authorizations.active, items: 10)
  end

  def destroy
    authorization = current_user.oauth_authorizations.active.find(params.expect(:id))

    Doorkeeper.config.application_model.revoke_tokens_and_grants_for(
      authorization.application_id,
      current_user
    )

    redirect_to user_oauth_authorizations_path, notice: "Application authorization revoked."
  end
end
