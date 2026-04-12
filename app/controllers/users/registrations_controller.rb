class Users::RegistrationsController < Devise::RegistrationsController
  helper Users::SessionsHelper
  layout :set_layout

  before_action :configure_sign_up_params, only: [:create]
  prepend_before_action :check_captcha, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  before_action :check_registration_allowed, only: %i[new create]

  # GET /resource/sign_up
  def new
    super
  end

  # POST /resource
  def create
    super
  rescue Postmark::InactiveRecipientError
    flash.now[:error] = render_to_string(partial: "devise/mailer/mta_error")
    resource.errors.add(:email, "was rejected by our email provider.")

    resource.destroy
    respond_with resource
  rescue Postmark::InvalidEmailRequestError
    resource.errors.add(:email, "is not a valid email address.")

    resource.destroy
    respond_with resource
  end

  # GET /resource/edit
  # def edit
  #   super
  # end

  # PUT /resource
  def update
    super do |resource|
      if resource.errors.empty? && resource.saved_change_to_encrypted_password?
        current_sid = request.env["rack.session.options"]&.[](:id)&.private_id
        resource.destroy_sessions_except(current_sid)
      end
    end
  end

  # DELETE /resource
  def destroy
    if request.format.turbo_stream? && params[:confirm_text].blank?
      self.resource = current_user
      render and return
    end
    super
  end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  protected def update_resource(resource, params)
    # Block update of protected fields (email, password) if the user has a password.
    if resource.has_password?
      return super if params[:password].present? || params[:password_confirmation].present?
      return super if params[:email].present? && params[:email] != current_user.email

      # If the user provides a current_password, validate it regardless.
      return super if params[:current_password].present?
    else
      if params[:password].present?
        resource.set_initial_password(params[:password], params[:password_confirmation])
      end
    end

    # NOTE: Devise filters params for us, so this is safe.
    params.delete(:current_password)
    resource.update_without_password(params)
  end

  protected def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [profile_attributes: [:display_name]])
  end

  protected def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [profile_attributes: [:display_name]])
  end

  def after_sign_up_path_for(resource)
    character_registrations_path
  end

  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end

  protected def after_update_path_for(resource)
    edit_user_path
  end

  protected def check_registration_allowed
    return if User.signup_permitted?

    sign_out current_user
    redirect_to new_user_session_path, alert: "Sign-ups are disabled at this time."
  end

  protected def check_captcha
    return if cloudflare_turnstile_ok?

    self.resource = resource_class.new sign_up_params
    resource.validate
    set_minimum_password_length

    flash[:alert] = "CAPTCHA verification failed. Please try again."
    render :new, status: :unprocessable_content
  end

  private def set_layout
    if action_name == "new" || action_name == "create"
      "login/signin"
    elsif action_name == "edit"
      "portal/base"
    else
      "portal/page"
    end
  end
end
