class Developer::Teams::InviteLinksController < Developer::DeveloperPortalController
  before_action :set_team, only: %i[new create]
  before_action :set_invite_link, only: %i[destroy accept_invite]

  skip_before_action :check_developer_role, only: %i[accept_invite]

  def new
    @invite_link = @team.invite_links.new
  end

  def create
    authorize! :manage_users, @team

    @invite_link = @team.invite_links.new(
      target_role: filtered_params[:target_role],
      usage_limit: (if filtered_params[:usage_limit].present? && filtered_params[:usage_limit].to_i.positive?
                      filtered_params[:usage_limit].to_i
                    end),
      expires_at: (if filtered_params[:expires_at].present? && filtered_params[:expires_at].to_i.positive?
                     Time.current + filtered_params[:expires_at].to_i.minutes
                   end)
    )

    respond_to do |format|
      if @invite_link.save
        format.html { redirect_to developer_team_path(@team), notice: "Invite link was successfully created." }
        format.turbo_stream { render "developer/teams/invite_links/success" }
      else
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def destroy
    redirect_to root_path, alert: "Team not found." if @team.blank?

    authorize! :manage_users, @team

    if @invite_link.destroy
      redirect_to developer_team_path(@team), notice: "Invite link was successfully deleted."
    else
      redirect_to developer_team_path(@team), alert: "Could not delete invite link."
    end
  end

  def accept_invite
    redirect_to root_path, alert: "Team invite link invalid." if @team.blank?

    membership = Team::Membership.new(team: @team, user: current_user)

    if membership.save
      redirect_to developer_team_path(@team), notice: "You have joined the team #{@team.name}!"
    else
      redirect_to root_path, alert: "Could not join the team: #{@team.name}"
    end
  end

  private def filtered_params
    params.expect(team_invite_link: %i[target_role usage_limit expires_at])
  end

  private def set_invite_link
    @invite_link = Team::InviteLink.find_by(invite_key: params[:code])
    @team = @invite_link&.team
  end

  private def set_team
    @team = Team.find(params.expect(:team_id))
  end
end
