class Developer::ClientApps::OboAuthorizationsController < Developer::DeveloperPortalController
  before_action :set_audience_app

  def new; end

  def create
    azp_app = ClientApplication.find(params.expect(:azp_id))
    authorize! :edit, @aud_app
    authorize! :use, azp_app

    @aud_app.obo_authorizations << azp_app

    if @aud_app.save
      respond_to do |format|
        format.html { redirect_to developer_application_path(@aud_app), notice: "Application authorized." }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to developer_application_path(@aud_app), warning: "Application could not be authorized."
        end
      end
    end
  end

  def destroy
    record = @aud_app.obo_authorizations.find(params.expect(:azp_id))
    authorize! :edit, @aud_app

    if @aud_app.obo_authorizations.delete(record)
      respond_to do |format|
        format.html { redirect_to developer_application_path(@aud_app), notice: "Application authorization removed." }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to developer_application_path(@aud_app), warning: "Application authorization could not be removed."
        end
      end
    end
  end

  private def set_audience_app
    @aud_app = ClientApplication.find(params.expect(:application_id))
  end
end
