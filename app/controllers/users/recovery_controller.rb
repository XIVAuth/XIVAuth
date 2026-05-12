class Users::RecoveryController < ApplicationController
  helper Users::SessionsHelper
  layout "login/signin"

  RECOVERY_MESSAGE = "Your recovery request was received. If your email is in our system, you should receive a " \
                     "recovery email shortly.".freeze

  skip_before_action :authenticate_user!
  prepend_before_action :check_captcha, only: [:create]

  def new
    @user = User.new
    render "devise/recovery/new"
  end

  def create
    if permitted_params[:email].blank?
      @user = User.new
      @user.errors.add(:email, "can't be blank")

      render "devise/recovery/new", status: :unprocessable_content
      return
    end

    @user = User.find_by(email: permitted_params[:email])

    if @user.nil?
      redirect_to new_user_session_path, notice: RECOVERY_MESSAGE
      return
    end

    if @user.confirmed?
      @user.send_reset_password_instructions
    else
      @user.resend_confirmation_instructions
    end

    redirect_to new_user_session_path, notice: RECOVERY_MESSAGE
  rescue Postmark::InactiveRecipientError
    # NOTE: This technically does enable an enumeration attack, but only for users that exist but can't receive emails.
    # It's better (imo) to explicitly tell the user that we can't reset their account so they don't end up waiting for
    # an email that never comes.
    flash.now[:error] = render_to_string(partial: "devise/mailer/mta_error")
    render "devise/recovery/new", status: :unprocessable_content
  end

  def permitted_params
    params.expect(user: [:email])
  end

  private def check_captcha
    return if cloudflare_turnstile_ok?

    flash.now[:alert] = "CAPTCHA verification failed. Please try again."
    @user = User.new
    render "devise/recovery/new", status: :unprocessable_content
  end
end
