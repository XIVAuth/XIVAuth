class Users::OAuthAuthorizationsController < ApplicationController
  layout "chroma/container"
  include Pagy::Method

  def index
    @pagy, @authorizations = pagy(current_user.oauth_authorizations.active, items: 10)
  end
end
