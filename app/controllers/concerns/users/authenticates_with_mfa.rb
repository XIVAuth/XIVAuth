module Users::AuthenticatesWithMFA
  extend ActiveSupport::Concern

  def authenticate_with_mfa
    if mfa_params[:otp_attempt].present? && session.dig("mfa")
      authenticate_with_totp
    elsif mfa_params[:webauthn_response].present? && session.dig("mfa")
      authenticate_with_webauthn
    elsif mfa_params[:bypass_mfa].present? && Rails.env.development? && session.dig("mfa")
      # local dev gets to bypass.
      handle_mfa_success
    else
      logger.error("MFA authentication attempt failed - missing params or no session data?")
      handle_mfa_failure("setup", message: "invalid context")
    end
  end

  def prompt_for_mfa(status_code: :ok, **extra_metadata)
    session["mfa"] ||= {}
    session["mfa"][:user_id] = @user.id
    session["mfa"].merge!(extra_metadata)

    # webauthn
    if (@webauthn_challenge = Users::Webauthn::AuthenticateService.build_challenge_for_user(@user))
      session["mfa"]["webauthn_challenge"] = @webauthn_challenge.challenge
    end

    render "devise/sessions/mfa", status: status_code
  end

  private def reset_mfa_attempt!
    session.delete("mfa")
  end

  private def authenticate_with_webauthn
    challenge_data = session.dig("mfa", "webauthn_challenge")
    verifier = Users::Webauthn::AuthenticateService.new(@user, mfa_params[:webauthn_response], challenge_data)

    verifier.execute
    handle_mfa_success
  rescue WebAuthn::Error => e
    handle_mfa_failure("WebAuthn", message: e.message)
  end

  private def authenticate_with_totp
    unless @user.totp_credential&.otp_enabled
      handle_mfa_failure("TOTP", message: "TOTP is not configured!")
      return
    end

    if @user.totp_credential.validate_and_consume_otp_or_backup!(mfa_params[:otp_attempt])
      handle_mfa_success
    else
      handle_mfa_failure("TOTP", message: "TOTP was invalid or could not be verified.")
    end
  end

  private def handle_mfa_success
    # Re-apply the pwned flag if MFA passed it along.
    if session.dig("mfa", "pwned")
      @user.instance_variable_set(:@pwned, true)
    end

    reset_mfa_attempt!
    sign_in(:user, @user)
  end

  private def handle_mfa_failure(method, message: nil)
    flash.now[:alert] = "MFA authentication via #{method} failed: #{message}"
    prompt_for_mfa(status_code: :unprocessable_content)
  end

  def mfa_params
    params.permit(mfa: [:otp_attempt, :webauthn_response, :bypass_mfa]).fetch(:mfa, {})
  end
end
