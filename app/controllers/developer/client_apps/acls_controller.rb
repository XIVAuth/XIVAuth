class Developer::ClientApps::AclsController < Developer::DeveloperPortalController
  before_action :set_application

  def new
    @acl = @application.acls.build
  end

  def create
    authorize! :manage, @application

    @acl = @application.acls.build(principal_type: acl_params[:principal_type], deny: acl_params[:deny])

    principal = resolve_principal(acl_params[:principal_type], acl_params[:principal_id])

    if principal.nil?
      @acl.errors.add(:principal_id, "could not be found")
      return render_form_error
    end

    @acl.principal = principal
    @acl.include_team_descendants = principal.is_a?(Team) && acl_params[:include_team_descendants] == "1"

    if @acl.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to developer_application_path(@application), notice: "ACL entry added." }
      end
    else
      render_form_error
    end
  end

  def destroy
    authorize! :manage, @application

    @acl = @application.acls.find(params.expect(:id))

    if @acl.destroy
      respond_to do |format|
        format.html { redirect_to developer_application_path(@application), notice: "ACL entry removed." }
      end
    else
      respond_to do |format|
        format.html { redirect_to developer_application_path(@application), alert: "Could not remove ACL entry." }
      end
    end
  end

  private def render_form_error
    render turbo_stream: turbo_stream.update("add_acl_modal-content",
                                             partial: "developer/client_apps/acls/form"),
           status: :unprocessable_content
  end

  private def set_application
    @application = ClientApplication.find(params.expect(:application_id))
    raise ActiveRecord::RecordNotFound unless can?(:manage, @application)
  end

  private def acl_params
    params.expect(acl: %i[principal_type principal_id deny include_team_descendants])
  end

  private def resolve_principal(type, id)
    case type
    when "User" then User.find_by(id: id)
    when "Team" then Team.find_by(id: id)
    end
  end
end
