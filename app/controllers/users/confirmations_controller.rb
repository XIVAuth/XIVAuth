class Users::ConfirmationsController < ApplicationController
  helper Users::SessionsHelper
  layout "login/signin"

  skip_before_action :authenticate_user!

  # Gmail's one-click ConfirmAction POSTs from Google's servers with no session or CSRF token; the single-use
  # confirmation token is what authorizes the request.
  skip_forgery_protection only: :one_click

  # GET /resource/confirmation?confirmation_token=abcdef
  def show
    @user = User.confirm_by_token(params[:confirmation_token])

    if @user.errors.empty?
      flash[:notice] = "Your account has been confirmed. Welcome to XIVAuth!"
      redirect_to stored_location_for(@user) || character_registrations_path
    else
      redirect_to user_recovery_path, alert: @user.errors.full_messages.join("\n")
    end
  end

  # POST /auth/register/confirm?confirmation_token=abcdef
  #
  # Target of the email's one-click action. Gmail only looks at the status code, and may retry, so an
  # already-confirmed token also counts as success.
  def one_click
    user = User.confirm_by_token(params[:confirmation_token])

    if user.errors.empty? || user.errors.of_kind?(:email, :already_confirmed)
      head :ok
    else
      head :bad_request
    end
  end
end
