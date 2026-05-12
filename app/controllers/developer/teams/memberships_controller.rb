class Developer::Teams::MembershipsController < Developer::DeveloperPortalController
  before_action :set_team
  before_action :set_membership

  def update
    authorize! :manage_users, @team

    if manager_restricted? && (target_is_privileged? || privileged_role_requested?)
      return redirect_to developer_team_path(@team), alert: "Managers cannot modify admin or manager memberships."
    end

    @membership.update(membership_params)

    respond_to do |format|
      format.turbo_stream
      format.html do
        if @membership.errors.any?
          redirect_to developer_team_path(@team), alert: @membership.errors.full_messages.first
        else
          redirect_to developer_team_path(@team), notice: "Role updated."
        end
      end
    end
  end

  def destroy
    authorize! :manage_users, @team

    if @membership.user == current_user
      return redirect_to developer_team_path(@team), alert: "You cannot remove yourself from a team."
    end

    if manager_restricted? && target_is_privileged?
      return redirect_to developer_team_path(@team), alert: "Managers cannot remove admin or manager members."
    end

    # First request: show confirmation modal
    render and return if request.format.turbo_stream? && params[:commit].blank?

    if @membership.destroy
      respond_to do |format|
        format.turbo_stream { render :destroy_confirmed }
        format.html { redirect_to developer_team_path(@team), notice: "Member removed." }
      end
    else
      redirect_to developer_team_path(@team), alert: @membership.errors.full_messages.first
    end
  end

  private def set_team
    @team = Team.find(params.expect(:team_id))
    authorize! :use, @team
  end

  private def set_membership
    @membership = @team.direct_memberships.find_by!(user_id: params.expect(:user_id))
  end

  private def membership_params
    params.expect(team_membership: [:role]).tap do |p|
      allowed = if can?(:manage, @team)
                  %w[admin manager developer member]
                else
                  %w[developer member]
                end
      p[:role] = nil unless allowed.include?(p[:role])
    end
  end

  private def manager_restricted?
    !can?(:manage, @team)
  end

  private def target_is_privileged?
    @membership.role.in?(%w[admin manager])
  end

  private def privileged_role_requested?
    params.dig(:team_membership, :role).in?(%w[admin manager])
  end
end
