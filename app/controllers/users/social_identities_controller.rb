class Users::SocialIdentitiesController < ApplicationController
  before_action :load_identity

  def destroy
    authorize! :destroy, @identity

    @identity.destroy

    redirect_to edit_user_path, notice: "Identity was removed."
  end

  private def load_identity
    @identity = User::SocialIdentity.find(params.expect(:id))
    authorize! :show, @identity
  end
end
