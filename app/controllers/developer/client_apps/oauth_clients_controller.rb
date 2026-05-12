class Developer::ClientApps::OAuthClientsController < Developer::DeveloperPortalController
  helper Developer::ClientApps::OAuthClientHelper
  layout "portal/base"

  before_action :set_oauth_client, except: %i[new create]

  def show; end

  def new
    @application = ClientApplication.find(params.expect(:application_id))
    @oauth_client = ClientApplication::OAuthClient.new
  end

  def create
    @application = ClientApplication.find(params.expect(:application_id))
    authorize! :edit, @application

    @oauth_client = ClientApplication::OAuthClient.new(filtered_params)
    @oauth_client.application = @application

    if @oauth_client.save
      flash[:notice] = "OAuth client created successfully."
      flash[:application_secret] = @oauth_client.plaintext_secret

      redirect_to developer_oauth_client_path(@oauth_client)
    else
      flash.now[:error] = "Could not create OAuth client."
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize! :edit, @application

    updates = filtered_params
    # Normalize array params by removing blank entries for keys that are present in this submission only
    %i[redirect_uris grant_flows scopes].each do |key|
      updates[key] = (updates[key] || []).compact_blank if updates.key?(key)
    end

    @oauth_client.update(updates)

    if params[:regenerate_secret].present?
      @oauth_client.renew_secret
      flash[:application_secret] = @oauth_client.plaintext_secret
    end

    if @oauth_client.save
      respond_to do |format|
        format.html { redirect_to developer_oauth_client_path(@oauth_client), notice: "Updated." }
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Update failed."
          redirect_back_or_to(developer_oauth_client_path(@oauth_client))
        end
      end
    end
  end

  def destroy
    authorize! :edit, @application

    render and return if request.format.turbo_stream? && params[:confirm_text].blank?

    if @oauth_client.destroy
      respond_to do |format|
        format.html { redirect_to developer_application_path(@application), notice: "OAuth client deleted." }
        format.turbo_stream { redirect_to developer_application_path(@application) }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to developer_oauth_client_path(@oauth_client),
                      status: :unprocessable_content,
                      error: "Could not delete OAuth client."
        end
        format.turbo_stream { redirect_to developer_oauth_client_path(@oauth_client) }
        format.json { render json: { error: "Could not delete OAuth client." }, status: :unprocessable_content }
      end
    end
  end

  def regenerate
    authorize! :edit, @application

    @oauth_client.renew_secret

    if @oauth_client.save
      flash[:application_secret] = @oauth_client.plaintext_secret

      respond_to do |format|
        format.html { redirect_to developer_oauth_client_path(@oauth_client), notice: "Secret regenerated!" }
        format.json { render json: @oauth_client, as_owner: true }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to developer_application_path(@application),
                      status: :unprocessable_content,
                      error: "Could not regenerate app secret."
        end
        format.json { render json: @oauth_client, as_owner: true }
      end
    end
  end

  private def set_oauth_client
    @oauth_client = ClientApplication::OAuthClient.find(params.expect(:id))
    @application = @oauth_client.application

    raise ActiveRecord::RecordNotFound unless can? :show, @application
  end

  private def filtered_params
    params.expect(oauth_client: [:name, :enabled, :expires_at, :confidential, :app_type,
                                 { redirect_uris: [], grant_flows: [], scopes: [] }])
  end
end
