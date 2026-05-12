class Users::TotpCredentialsController < ApplicationController
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

    otp_attempt = params.dig(:user_totp_credential, :otp_attempt)

    # If TOTP code isn't present, the user just clicked on the button.
    render and return if otp_attempt.nil?

    unless @totp_credential.validate_and_consume_otp_or_backup!(otp_attempt)
      @totp_credential.errors.add(:otp_attempt, "was invalid")
      render status: :unprocessable_content,
             turbo_stream: turbo_stream.update("remove_totp_modal-content",
                                               partial: "users/totp_credentials/destroy_modal")

      return
    end

    if @totp_credential.delete
      flash[:notice] = "TOTP credential successfully removed."
    else
      flash[:error] = "TOTP credential could not be removed."
    end

    redirect_to edit_user_path
  end

  def regenerate_backup
    @totp_credential = current_user.totp_credential
    otp_attempt = params.dig(:user_totp_credential, :otp_attempt)

    # If TOTP code isn't present, the user just clicked on the button.
    render and return if otp_attempt.nil?

    unless @totp_credential.validate_and_consume_otp_or_backup!(otp_attempt)
      @totp_credential.errors.add(:otp_attempt, "was invalid")
      render status: :unprocessable_content,
             turbo_stream: turbo_stream.update("regenerate_totp_backup_modal-content",
                                               partial: "users/totp_credentials/regenerate_check_modal")

      return
    end

    @backup_codes = @totp_credential.generate_otp_backup_codes!
    if @totp_credential.save
      render status: :ok,
             turbo_stream: turbo_stream.update("regenerate_totp_backup_modal-content",
                                               partial: "users/totp_credentials/regenerate_success_modal")
    else
      redirect_to edit_user_path, error: "TOTP backup codes could not be regenerated."
    end
  end

  private def render_new_form_again(status: :unprocessable_content)
    render status: status,
           turbo_stream: turbo_stream.update("register_totp_modal-content", partial: "users/totp_credentials/new_modal")
  end

  private def filtered_params
    params.expect(user_totp_credential: [:otp_attempt])
  end
end
