class Developer::OnboardingController < Developer::DeveloperPortalController
  layout "portal/base"
  skip_before_action :check_developer_role

  def show
    return unless current_user.role?(:developer)

    redirect_to developer_applications_path, notice: "Developer mode is already enabled on your account."
  end

  def enable
    user = current_user

    if user.role?(:developer)
      redirect_to developer_applications_path, notice: "Developer Mode is already enabled on your account."
      return
    end

    unless user.mfa_enabled_or_passwordless?
      redirect_to developer_onboarding_path, alert: "Multi-factor authentication is required to enable Developer Mode."
      return
    end

    unless user.character_registrations.verified.any?
      redirect_to developer_onboarding_path,
                  alert: "At least one verified character is required to enable Developer Mode."
      return
    end

    if params[:agree].blank?
      redirect_to developer_onboarding_path,
                  alert: "You must read and agree to the Developer Agreement to enable Developer Mode."
      return
    end

    user.add_role :developer

    if user.save
      redirect_to developer_applications_path, notice: "Developer Mode enabled!"
    else
      redirect_to developer_onboarding_path, alert: "Could not enable Developer Mode. Please try again later."
    end
  end
end
