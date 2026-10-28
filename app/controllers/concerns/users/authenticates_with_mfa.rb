module Users::AuthenticatesWithMFA
  extend ActiveSupport::Concern

  def authenticate_with_mfa
    unless session["mfa"]
      logger.error("MFA authentication attempt failed - no session data?")
      handle_mfa_failure("setup", message: "invalid context")
      return
    end

    # local dev gets to bypass.
    if mfa_params[:bypass_mfa].present? && Rails.env.development?
      handle_mfa_success(:bypass)
      return
    end

    method = Users::MFAVerifier.new(
      @user,
      otp_attempt: mfa_params[:otp_attempt],
      webauthn_response: mfa_params[:webauthn_response],
      webauthn_challenge: session.dig("mfa", "webauthn_challenge")
    ).verify!

    handle_mfa_success(method)
  rescue Users::MFAVerifier::VerificationError => e
    handle_mfa_failure(e.method, message: e.message)
  end

  def prompt_for_mfa(status_code: :ok, **extra_metadata)
    session["mfa"] = {
      user_id: @user.id
    }.merge(extra_metadata)

    # webauthn
    if (@webauthn_challenge = Users::Webauthn::AuthenticateService.build_challenge_for_user(@user))
      session["mfa"]["webauthn_challenge"] = @webauthn_challenge.challenge
    end

    render "devise/sessions/mfa", status: status_code
  end

  private def reset_mfa_attempt!
    session.delete("mfa")
  end

  private def handle_mfa_success(method)
    # Check for pwn status before clearing everything out, and set the flash.
    self.flash[:modal] = :password_breached_warning if session.dig("mfa", "pwned")

    reset_mfa_attempt!
    sign_in(:user, @user)

    # MFA is only prompted after a password.
    Users::AuthnContext.new(session).record_login!(["pwd", Users::AuthnContext::MFA_AMR[method]], mfa: true)
  end

  private def handle_mfa_failure(method, message: nil)
    flash.now[:alert] = "MFA authentication via #{method} failed: #{message}"
    prompt_for_mfa(status_code: :unprocessable_content, pwned: session.dig("mfa", "pwned"))
  end

  def mfa_params
    params.permit(mfa: %i[otp_attempt webauthn_response bypass_mfa]).fetch(:mfa, { })
  end
end
