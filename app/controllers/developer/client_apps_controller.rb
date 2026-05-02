class Developer::ClientAppsController < Developer::DeveloperPortalController
  layout "portal/base"
  include Pagy::Method
  helper Doorkeeper::DashboardHelper

  before_action :load_available_owners, only: %i[new create]
  before_action :set_application, only: %i[show edit update destroy regenerate transfer update_transfer]

  def index
    @pagy, @applications = pagy(accessible_applications, items: 24)

    respond_to do |format|
      format.html { render :index, layout: "portal/base" }
      format.json { head :no_content }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @application, as_owner: true }
    end
  end

  def new
    @application = ClientApplication.new
  end

  def create
    @application = ClientApplication.new(application_params)

    if create_application_params[:owner_id].present?
      owning_team = Team.find_by(id: create_application_params[:owner_id])

      unless can? :create_apps, owning_team
        @application.errors.add(:owner_id, :not_developer, message: "you do not have permission to create applications for this team")
        return render :new, status: :unprocessable_content
      end
      @application.owner = owning_team
    else
      @application.owner = current_user
    end

    if @application.save
      flash[:notice] = I18n.t(:notice, scope: %i[doorkeeper flash applications create])

      respond_to do |format|
        format.html { redirect_to developer_application_path(@application) }
        format.json { render json: @application, as_owner: true }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        format.json do
          errors = @application.errors.full_messages

          render json: { errors: }, status: :unprocessable_content
        end
      end
    end
  end

  def destroy
    authorize! :destroy, @application

    render and return if request.format.turbo_stream? && params[:confirm_text].blank?

    flash[:notice] = "Application destroyed." if @application.destroy

    respond_to do |format|
      format.html { redirect_to developer_applications_url }
      format.turbo_stream { redirect_to developer_applications_url }
      format.json { head :no_content }
    end
  end

  def transfer
    authorize! :manage, @application
    @transferable_teams = transferable_teams_for(@application)

    respond_to do |format|
      format.turbo_stream
      format.html { render :transfer }
    end
  end

  def update
    authorize! :update, @application

    if @application.update(application_params)
      flash[:notice] = "Application updated successfully"

      respond_to do |format|
        format.html { redirect_to developer_application_path(@application) }
        format.json { render json: @application, as_owner: true }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json do
          errors = @application.errors.full_messages

          render json: { errors: errors }, status: :unprocessable_content
        end
      end
    end
  end

  def update_transfer
    authorize! :manage, @application
    @transferable_teams = transferable_teams_for(@application)
    target_team_id = transfer_params[:owner_id]

    if target_team_id.blank?
      @application.errors.add(:owner_id, "must be selected")
      return render :transfer, status: :unprocessable_content
    end

    target_team = @transferable_teams.find_by(id: target_team_id)
    unless target_team
      @application.errors.add(:owner_id, "is not a valid transfer target")
      return render :transfer, status: :unprocessable_content
    end

    @application.owner = target_team

    if @application.save
      flash[:notice] = "Application transferred successfully."
      respond_to do |format|
        format.html { redirect_to developer_application_path(@application) }
      end
    else
      render :transfer, status: :unprocessable_content
    end
  end

  private def load_available_owners
    # Build owner options: current user + teams where user is a developer
    @available_owners = [["Your Account", ""]]

    current_user.teams_by_membership_scope(:developers).order(:name).each do |team|
      @available_owners << [team.name, team.id]
    end
  end

  private def accessible_applications
    ClientApplication.where(owner: current_user).or(ClientApplication.where(owner: current_user.associated_teams))
  end

  private def set_application
    @application = ClientApplication.find(params[:id])

    # specifically show RecordNotFound if we can't see it, rather than 403.
    raise ActiveRecord::RecordNotFound unless can? :show, @application
  end

  private def application_params
    params.require(:client_application)
          .permit(:name, :private, :icon, profile_attributes: [:homepage_url, :privacy_policy_url, :terms_of_service_url])
  end

  private def create_application_params
    params.require(:client_application)
          .permit(:name, :private, :owner_id, :icon,
                  profile_attributes: [:homepage_url, :privacy_policy_url, :terms_of_service_url])
  end

  private def transferable_teams_for(application)
    developer_teams = current_user.teams_by_membership_scope(:developers)

    if application.owner.is_a?(User)
      developer_teams
    elsif application.owner.is_a?(Team)
      hierarchy_ids = application.owner.antecedent_team_ids + application.owner.descendant_team_ids + [application.owner.id]
      developer_teams.where(id: hierarchy_ids)
    else
      Team.none
    end
  end

  private def transfer_params
    params.require(:client_application).permit(:owner_id)
  end
end
