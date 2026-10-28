class Users::TotpCredentialsController < ApplicationController
  include Users::RequiresSudo

  requires_sudo only: %i[new create], within: 5.minutes, and_rerender: :render_sudo_challenge
  requires_sudo only: :destroy, within: 0, and_rerender: :render_destroy_modal
  requires_sudo only: :regenerate_backup, within: 0, and_rerender: :render_regenerate_modal

  def new
    if current_user.totp_credential&.otp_enabled
      redirect_to edit_user_path, error: "TOTP has already been enabled."
      return
    end

    @totp_credential = User::TotpCredential.new(
      user_id: current_user.id,
      otp_secret: User::TotpCredential.generate_otp_secret
    )

    session[:staged_totp_secret] = @totp_credential.otp_secret
  end

  def create
    return if current_user.totp_credential&.otp_enabled

    @totp_credential = User::TotpCredential.new(
      user_id: current_user.id,
      otp_secret: session[:staged_totp_secret],
      otp_enabled: true
    )

    @backup_codes = @totp_credential.generate_otp_backup_codes!

    # perform rails validations first
    unless @totp_credential.valid?
      @totp_credential.errors.add(:base, "TOTP credential could not be created. Please try again.")
      render_new_form_again
      return
    end

    # Also will save here!
    unless @totp_credential.validate_and_consume_otp!(filtered_params[:otp_attempt])
      @totp_credential.errors.add(:otp_attempt, "was invalid")
      render_new_form_again
      return
    end

    # flash so we can update ui
    @totp_credential.save
    current_user.reload

    session.delete(:staged_totp_secret)
  end

  def destroy
    @totp_credential = current_user.totp_credential

    if @totp_credential.delete
      flash[:notice] = "TOTP credential successfully removed."
    else
      flash[:error] = "TOTP credential could not be removed."
    end

    redirect_to edit_user_path
  end

  def regenerate_backup
    @totp_credential = current_user.totp_credential
    @backup_codes = @totp_credential.generate_otp_backup_codes!
    if @totp_credential.save
      render status: :ok,
             turbo_stream: turbo_stream.update("regenerate_totp_backup_modal-content",
                                               partial: "users/totp_credentials/regenerate_success_modal")
    else
      redirect_to edit_user_path, error: "TOTP backup codes could not be regenerated."
    end
  end

  private def render_sudo_challenge(error: nil)
    render_sudo_modal(modal_id: "register_totp_modal", partial: "users/sudo_mode/modal_challenge",
                      locals: { title: "Set Up Authenticator App", url: new_user_totp_credential_path },
                      error: error, update: error.present? || action_name == "create")
  end

  private def render_destroy_modal(error: nil)
    @totp_credential = current_user.totp_credential
    render_sudo_modal(modal_id: "remove_totp_modal", partial: "users/totp_credentials/destroy_modal", error: error)
  end

  private def render_regenerate_modal(error: nil)
    @totp_credential = current_user.totp_credential
    render_sudo_modal(modal_id: "regenerate_totp_backup_modal",
                      partial: "users/totp_credentials/regenerate_check_modal", error: error)
  end

  private def render_new_form_again(status: :unprocessable_content)
    render status: status,
           turbo_stream: turbo_stream.update("register_totp_modal-content", partial: "users/totp_credentials/new_modal")
  end

  private def filtered_params
    params.expect(user_totp_credential: [:otp_attempt])
  end
end
