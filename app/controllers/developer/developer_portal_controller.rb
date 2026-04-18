class Developer::DeveloperPortalController < ApplicationController
  before_action :check_developer_role
  skip_before_action :check_developer_role, only: %i[docs]

  def docs
    redirect_to "https://kazwolfe.notion.site/Documentation-128e77f0016c4901888ea1234678c37d", allow_other_host: true
  end

  private def check_developer_role
    unless current_user.role?(:developer)
      redirect_to developer_onboarding_path
    end
  end
end