class Users::WebauthnCredentialsController < ApplicationController
  include Users::RequiresSudo

  requires_sudo only: %i[new create], within: 5.minutes, and_rerender: :render_sudo_challenge
  requires_sudo only: :destroy, within: 0, and_rerender: :render_destroy_modal

  def new
    if current_user.webauthn_id.nil?
      current_user.update(webauthn_id: WebAuthn.generate_user_id)
      current_user.save!
    end

    @webauthn_credential = User::WebauthnCredential.new
    @challenge = build_registration_challenge
  end

  def create
    credential_json = JSON.parse(create_params[:credential])
    recovered_credential = WebAuthn::Credential.from_create(credential_json)

    begin
      recovered_credential.verify(session[:webauthn_register_challenge])

      @webauthn_credential = current_user.webauthn_credentials.new(
        external_id: recovered_credential.id,
        public_key: recovered_credential.public_key,
        nickname: create_params[:nickname],
        sign_count: recovered_credential.sign_count,
        transports: recovered_credential.response&.transports,
        aaguid: recovered_credential.response&.aaguid,
        resident_key: recovered_credential.client_extension_outputs&.dig("credProps", "rk") || false,
        raw_data: credential_json
      )

      if @webauthn_credential.save
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("mfa-settings", partial: "devise/registrations/sections/mfa_settings",
                                   locals: { resource: current_user }),
              turbo_stream.append("register_webauthn_modal-content", partial: "layouts/components/remote_modal_close")
            ]
          end
          format.html { redirect_to edit_user_path, notice: "Credential was added." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render_new_form_again }
          format.html { render :new, status: :unprocessable_content }
        end
      end
    rescue WebAuthn::Error => e
      logger.error("Error while registering webauthn credential!", e)

      respond_to do |format|
        format.turbo_stream { render_new_form_again }
        format.html { render :new, status: :unprocessable_content }
      end
    ensure
      session.delete(:webauthn_register_challenge)
    end
  end

  def destroy
    credential = current_user.webauthn_credentials.find(params.expect(:id))

    if credential.destroy
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("mfa-settings", partial: "devise/registrations/sections/mfa_settings",
                                 locals: { resource: current_user }),
            turbo_stream.append("remove_webauthn_modal-content", partial: "layouts/components/remote_modal_close")
          ]
        end
        format.html { redirect_to edit_user_path, notice: "Credential was removed." }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_user_path, error: "Credential could not be deleted." }
      end
    end
  end

  private def render_sudo_challenge(error: nil)
    render_sudo_modal(modal_id: "register_webauthn_modal", partial: "users/sudo_mode/modal_challenge",
                      locals: { title: "Add Security Key", url: new_user_webauthn_credential_path },
                      error: error, update: error.present? || action_name == "create")
  end

  private def render_destroy_modal(error: nil)
    @webauthn_credential = current_user.webauthn_credentials.find(params.expect(:id))
    render_sudo_modal(modal_id: "remove_webauthn_modal", partial: "users/webauthn_credentials/destroy_modal",
                      error: error)
  end

  private def render_new_form_again(status: :unprocessable_content)
    @challenge = build_registration_challenge

    render status: status,
           turbo_stream: turbo_stream.update("register_webauthn_modal-content",
                                             partial: "users/webauthn_credentials/modal")
  end

  private def create_params
    params
      .expect(user_webauthn_credential: %i[credential nickname])
  end

  private def build_registration_challenge
    create_options = WebAuthn::Credential.options_for_create(
      user: {
        id: current_user.webauthn_id,
        display_name: current_user.email,
        name: current_user.email
      },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      authenticator_selection: {
        # Discourage resident keys to prevent yubikey pain.
        # UV for registration is irrelevant - assume the user is authorized.
        resident_key: "discouraged"
      },
      attestation: "none",
      extensions: {
        cred_props: true
      }
    )

    session[:webauthn_register_challenge] = create_options.challenge

    create_options
  end
end
