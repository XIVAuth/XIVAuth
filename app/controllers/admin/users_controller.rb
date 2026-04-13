class Admin::UsersController < Admin::AdminController
  include Pagy::Method

  before_action :set_user, except: %i[index]
  layout "portal/base"

  def index
    users = User.includes(:profile, :social_identities, :character_registrations)
                .order(created_at: :desc)
    @pagy, @users = pagy(users)
  end

  def show
    @pagy_cregs, @cregs = pagy(@user.character_registrations, page_key: "page_cr", items: 10)
  end

  def destroy
    if @user.destroy
      redirect_to admin_users_path, notice: "User deleted."
    else
      redirect_to admin_user_path(@user), alert: "User could not be deleted."
    end
  end

  def destroy_mfa
    @user.webauthn_credentials.clear
    @user.totp_credential = nil

    if @user.save
      flash[:notice] = "MFA was removed for user."
    else
      flash[:error] = "MFA could not be removed for user."
    end

    redirect_back_or_to admin_user_path(@user)
  end

  def send_password_reset
    token = @user.send_reset_password_instructions

    if token
      respond_to do |format|
        format.turbo_stream do
          render partial: "admin/users/reset_password_modal", locals: {
            reset_password_token: reset_user_password_url(reset_password_token: token),
            link_ttl: Devise.reset_password_within.inspect
          }
        end
        format.html do
          flash[:notice] = "A password reset email was sent to #{@user.email}."
          redirect_back_or_to admin_user_path(@user)
        end
      end
    else
      flash[:error] = "Could not dispatch a password reset email."
      redirect_back_or_to admin_user_path(@user)
    end
  end

  def destroy_all_sessions
    # Note: will not terminate own current session.
    @user.destroy_sessions(@user.get_sessions.map { |s| s[:sid] })
    redirect_back_or_to admin_user_path(@user), notice: "All sessions for #{@user.email} have been terminated."
  end

  def confirm
    if @user.confirm
      flash[:notice] = "The user was successfully confirmed."
    else
      flash[:error] = "Could not confirm user."
    end

    redirect_back_or_to admin_user_path(@user)
  end

  private def set_user
    @user = User.find(params[:id])
  end
end
