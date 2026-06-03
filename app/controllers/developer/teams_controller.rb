class Developer::TeamsController < Developer::DeveloperPortalController
  layout "chroma/page"
  include Pagy::Method

  before_action :load_parent_teams, only: %i[new create]
  before_action :set_team, only: %i[show update destroy leave]
  skip_before_action :check_developer_role, only: %i[index leave]
  before_action :check_team_list_access, only: %i[index]

  def index
    @pagy, @teams = pagy(current_user.teams.order(created_at: :desc), items: 12)

    respond_to do |format|
      format.html { render :index }
      format.json { head :no_content }
    end
  end

  def show
    unless can?(:show, @team)
      redirect_to developer_teams_path, alert: "You don't have permission to view this team's details."
      return
    end

    respond_to do |format|
      format.html { render :show }
      format.json { render json: @team, as_owner: true }
    end
  end

  def new
    @team = Team.new
    @team.parent_id = params[:parent_id] if params[:parent_id].present?
  end

  def create
    @team = Team.new(create_team_params)

    if @team.parent_id.blank?
      @team.direct_memberships.build(user: current_user, role: "admin")
    else
      unless @available_parent_teams.find_by(id: @team.parent_id)
        @team.errors.add(:parent_id, "you must be an admin of the parent team")
        return respond_to do |format|
          format.html { render :new, status: :unprocessable_content }
        end
      end
    end

    if @team.save
      redirect_to developer_team_path(@team), notice: "Team was successfully created."
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def leave
    membership = @team.direct_memberships.find_by(user: current_user)

    if membership.nil?
      redirect_to developer_teams_path, alert: "You can only leave teams you are a direct member of."
      return
    end

    if membership.destroy
      redirect_to developer_teams_path, notice: "You have left #{@team.name}."
    else
      redirect_to developer_teams_path, alert: membership.errors.full_messages.first
    end
  end

  def update
    authorize! :update, @team

    if @team.readonly?
      flash[:alert] = "This is a system team and cannot be modified."
      return redirect_to developer_team_path(@team)
    end

    @team.icon&.destroy if params.dig(:team, :remove_icon) == "1"

    if @team.update(update_team_params)
      flash[:notice] = "Team updated successfully."
      redirect_to developer_team_path(@team)
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_content }
      end
    end
  end

  def destroy
    authorize! :destroy, @team

    render and return if request.format.turbo_stream? && params[:confirm_text].blank?

    if @team.destroy
      flash[:notice] = "Team destroyed."
    else
      flash[:alert] = @team.errors.full_messages.first || "Unable to delete team"
    end

    respond_to do |format|
      format.html { redirect_to developer_teams_url }
      format.turbo_stream { redirect_to developer_teams_url }
      format.json { head :no_content }
    end
  end

  private def set_team
    @team = Team.find(params.expect(:id))

    authorize! :use, @team

    direct = @team.direct_memberships.includes(:user).to_a
    inherited = @team.antecedent_memberships.includes(:user, :team).to_a
    role_order = Team::Membership.roles.keys
    @all_memberships = (direct + inherited).sort_by { |m| role_order.index(m.role) || role_order.size }
  end

  private def load_parent_teams
    @available_parent_teams = current_user.teams_by_membership_scope(:admins)
                                          .order(:name)
                                          .distinct
  end

  private def create_team_params
    params.expect(team: %i[name parent_id])
  end

  private def update_team_params
    params.expect(team: %i[name inherit_parent_memberships icon])
  end

  private def check_team_list_access
    check_developer_role unless current_user.team_memberships.any?
  end
end
