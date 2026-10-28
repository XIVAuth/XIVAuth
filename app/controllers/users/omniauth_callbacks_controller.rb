class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: [:steam] # rubocop:disable Rails/LexicallyScopedActionFilter

  User.omniauth_providers.each do |provider|
    next if self.method_defined?(provider)

    define_method(provider) do
      @provider = provider
      common
    end
  end

  def callback
    @provider = params[:provider]

    raise "Unknown OAuth provider: #{@provider}" unless User.omniauth_providers.include? @provider

    common
  end

  private def common
    return sso_bind_identity if user_signed_in?

    unless User.omniauth_login_providers.include? @provider
      raise "Cannot proceed with authentication for a non-login provider."
    end

    sso_signin
  end

  private def sso_signin
    raise "sso_signin called while a user was logged in!" if user_signed_in?

    user = sign_in_via_known_identity || sign_in_via_unknown_identity
    return if performed?

    if user.persisted?
      set_flash_message(:notice, :success, kind: auth_data["provider"].camelize) if is_navigational_format?
      sign_in_and_redirect user, event: :authentication
      Users::AuthnContext.new(session).record_login!(%w[fed])
    else
      session["devise.oauth.data"] = auth_data.except(:extra)
      redirect_to new_user_registration_path, alert: user.errors.full_messages.join("\n")
    end
  end

  # Attempt an authentication with a known social identity. Refresh data if present.
  private def sign_in_via_known_identity
    identity = User::SocialIdentity.find_by(provider: auth_data.provider, external_id: auth_data.uid)
    return if identity.blank?

    identity.merge_auth_hash(auth_data)
    identity.touch_used_at
    identity.user
  end

  # Attempt an authentication (or registration) with an unknown social identity.
  private def sign_in_via_unknown_identity
    unless User.omniauth_login_providers.include? @provider
      redirect_to new_user_session_path, alert: "#{provider_name} accounts cannot be used for authentication."
      return
    end

    # If the provider doesn't give us an email, we can't bind. Ask the user to sign in and then authenticate.
    email = auth_data.dig(:info, :email)&.downcase
    return redirect_link_required if email.blank?

    existing_user = User.find_for_database_authentication(email: email)

    if existing_user.present?
      bind_to_existing_user(existing_user)
    else
      register_new_user
    end
  end

  private def bind_to_existing_user(user)
    return redirect_link_required if user.mfa_enabled?

    user.add_social_identity(auth_data)
    return user if user.save

    redirect_to new_user_session_path, alert: user.errors.full_messages.join("\n")
    nil
  end

  private def register_new_user
    unless User.signup_permitted?
      redirect_to new_user_session_path, alert: "Sign-ups are disabled at this time."
      return
    end

    User.new_with_omniauth(auth_data).tap(&:save)
  end

  private def redirect_link_required
    redirect_to new_user_session_path,
                alert: "You must link your #{provider_name} account before you can use it for sign in. Please log " \
                       "in and link your #{provider_name} account first."
    nil
  end

  private def provider_name
    @provider.to_s.titleize
  end

  private def sso_bind_identity
    identity = User::SocialIdentity.find_by(provider: auth_data[:provider], external_id: auth_data[:uid])
    if identity.present?
      if identity.user == current_user
        identity.merge_auth_hash(auth_data)

        redirect_to edit_user_path, alert: "This social identity already exists on your account! " \
                                           "Information about this identity has been updated."
      else
        redirect_to edit_user_path, alert: "This social identity is already used on another account. " \
                                           "Please delete it from that account first."
      end

      return
    end

    identity = current_user.add_social_identity(auth_data)

    if identity.save
      set_flash_message(:notice, :success, kind: auth_data["provider"].camelize) if is_navigational_format?
      redirect_to edit_user_path
    else
      redirect_to edit_user_path, alert: identity.errors.full_messages.join("\n")
    end
  end

  private def auth_data
    request.env["omniauth.auth"]
  end
end
