class Admin::ClientApplicationsController < Admin::AdminController
  include Pagy::Method

  layout "portal/base"

  before_action :set_app, only: %i[show destroy]

  def index
    @pagy, @client_applications = pagy(ClientApplication.includes(:profile, owner: :profile).order(created_at: :desc))
  end

  def show; end

  def destroy
    if @client_application.destroy
      redirect_to admin_client_applications_path, notice: "Client application deleted."
    else
      redirect_to admin_client_application_path(@client_application), alert: "Client application could not be deleted."
    end
  end

  private def set_app
    @client_application = ClientApplication.find(params.expect(:id))
  end
end
