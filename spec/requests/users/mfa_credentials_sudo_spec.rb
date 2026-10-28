require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Sudo mode for MFA credentials" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { FactoryBot.create(:user) }
  let(:totp_secret) { ROTP::Base32.random }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  def valid_otp
    ROTP::TOTP.new(totp_secret).now
  end

  before { sign_in user }

  context "when the user has TOTP enabled" do
    let!(:totp_credential) do
      FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
    end

    describe "DELETE /profile/totp" do
      it "opens the removal modal with the challenge embedded" do
        delete user_totp_credential_path, headers: turbo

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("remove_totp_modal").and include("sudo[otp_attempt]")
        expect(user.reload.totp_credential).to be_present
      end

      it "re-renders the modal with an error for a bad code" do
        delete user_totp_credential_path, params: { sudo: { otp_attempt: "000000", prompted: "1" } }, headers: turbo

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("remove_totp_modal-content").and include("failed")
        expect(user.reload.totp_credential).to be_present
      end

      it "re-renders the modal with an error when submitted empty" do
        delete user_totp_credential_path, params: { sudo: { prompted: "1" } }, headers: turbo

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("remove_totp_modal-content")
      end

      it "removes the credential with a valid code" do
        delete user_totp_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo

        expect(response).to redirect_to(edit_user_path)
        expect(user.reload.totp_credential).to be_nil
      end

      it "still requires a code when a recent grant exists" do
        post new_user_totp_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo
        delete user_totp_credential_path, headers: turbo

        expect(user.reload.totp_credential).to be_present
      end
    end

    describe "POST /profile/totp/regenerate_backup" do
      it "regenerates codes with a valid code" do
        old_codes = totp_credential.otp_backup_codes

        post regenerate_backup_user_totp_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo

        expect(response.body).to include("regenerate_totp_backup_modal-content")
        expect(totp_credential.reload.otp_backup_codes).not_to eq(old_codes)
      end
    end

    describe "adding a security key" do
      it "challenges first" do
        get new_user_webauthn_credential_path, headers: turbo

        expect(response.body).to include("register_webauthn_modal").and include("sudo[otp_attempt]")
        expect(response.body).not_to include("Register Security Key")
      end

      it "shows the registration form in the same modal after a valid code" do
        post new_user_webauthn_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo

        expect(response.body).to include("register_webauthn_modal-content").and include("Register Security Key")
      end

      it "skips the challenge within the grant window" do
        post new_user_webauthn_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo
        get new_user_webauthn_credential_path, headers: turbo

        expect(response.body).to include("Register Security Key")
      end
    end
  end

  context "when the user has a security key" do
    let!(:credential) { FactoryBot.create(:users_webauthn_credential, user: user) }

    before do
      FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
    end

    describe "DELETE /profile/webauthn/:id" do
      it "opens a confirmation modal with the challenge embedded" do
        delete user_webauthn_credential_path(credential), headers: turbo

        expect(response.body).to include("remove_webauthn_modal").and include("sudo[otp_attempt]")
        expect(user.webauthn_credentials.reload).to include(credential)
      end

      it "removes the key with a valid proof and closes the modal" do
        delete user_webauthn_credential_path(credential), params: { sudo: { otp_attempt: valid_otp } }, headers: turbo

        expect(response.body).to include("remoteCloseTrigger")
        expect(user.webauthn_credentials.reload).not_to include(credential)
      end
    end
  end

  context "when the user has no MFA" do
    it "opens the TOTP setup form without a challenge" do
      get new_user_totp_credential_path, headers: turbo

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("register_totp_modal").and include("Register Authenticator")
    end
  end

  # An attacker holding a session skips the challenge UI and submits the real form directly. Each case has a positive
  # control showing the identical request succeeds with a fresh grant, so a block can only come from the sudo gate.
  describe "direct submissions without a fresh grant" do
    let(:user) { FactoryBot.create(:user, webauthn_id: WebAuthn.generate_user_id) }
    let(:fake_client) { WebAuthn::FakeClient.new("http://localhost:3000", encoding: :base64url) }

    # Registers a key on `fake_client` so it can answer sudo challenges.
    def register_existing_key
      options = WebAuthn::Credential.options_for_create(user: { id: user.webauthn_id, name: user.email })
      recovered = WebAuthn::Credential.from_create(fake_client.create(challenge: options.challenge))

      FactoryBot.create(:users_webauthn_credential, user: user, external_id: recovered.id,
                                                    public_key: recovered.public_key, sign_count: 0)
    end

    describe "POST /profile/webauthn (add a security key)" do
      before do
        FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
      end

      # Passes the challenge legitimately to obtain a registration challenge, then builds a new key's attestation.
      def staged_registration_params
        post new_user_webauthn_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo
        attestation = WebAuthn::FakeClient.new("http://localhost:3000", encoding: :base64url)
                                          .create(challenge: session[:webauthn_register_challenge])

        { user_webauthn_credential: { nickname: "Attacker Key", credential: attestation.to_json } }
      end

      it "accepts the registration with a fresh grant (control)" do
        params = staged_registration_params

        expect { post user_webauthn_credentials_path, params: params, headers: turbo }
          .to change { user.webauthn_credentials.count }.by(1)
      end

      it "blocks the registration once the grant has expired" do
        params = staged_registration_params
        travel 6.minutes

        expect { post user_webauthn_credentials_path, params: params, headers: turbo }
          .not_to(change { user.webauthn_credentials.count })
        expect(response.body).to include("register_webauthn_modal-content").and include("sudo[otp_attempt]")
      end
    end

    describe "POST /profile/totp (add an authenticator app)" do
      let!(:existing_key) { register_existing_key }

      # Passes the challenge with the existing security key, which stages a TOTP secret, then answers with a valid
      # code for that secret.
      def staged_totp_params
        get new_user_totp_credential_path, headers: turbo
        assertion = fake_client.get(challenge: session[:sudo_webauthn_challenge], sign_count: 1)
        post new_user_totp_credential_path, params: { sudo: { webauthn_response: assertion.to_json } }, headers: turbo

        { user_totp_credential: { otp_attempt: ROTP::TOTP.new(session[:staged_totp_secret]).now } }
      end

      it "enables TOTP with a fresh grant (control)" do
        params = staged_totp_params
        post user_totp_credential_path, params: params, headers: turbo

        expect(user.reload.totp_credential&.otp_enabled).to be(true)
      end

      it "blocks enabling TOTP once the grant has expired" do
        params = staged_totp_params
        travel 6.minutes
        params[:user_totp_credential][:otp_attempt] = ROTP::TOTP.new(session[:staged_totp_secret]).now

        post user_totp_credential_path, params: params, headers: turbo

        expect(user.reload.totp_credential).to be_nil
        expect(response.body).to include("register_totp_modal-content").and include("Use Security Key")
      end
    end

    describe "POST /profile/totp/regenerate_backup" do
      let!(:totp_credential) do
        FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
      end

      it "regenerates with a valid code (control)" do
        expect { post regenerate_backup_user_totp_credential_path, params: { sudo: { otp_attempt: valid_otp } } }
          .to(change { totp_credential.reload.otp_backup_codes })
      end

      it "keeps the existing codes without a proof" do
        expect { post regenerate_backup_user_totp_credential_path, headers: turbo }
          .not_to(change { totp_credential.reload.otp_backup_codes })
        expect(response.body).to include("regenerate_totp_backup_modal").and include("sudo[otp_attempt]")
      end

      it "keeps the existing codes with a bad proof" do
        expect do
          post regenerate_backup_user_totp_credential_path, params: { sudo: { otp_attempt: "000000" } }, headers: turbo
        end.not_to(change { totp_credential.reload.otp_backup_codes })
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "keeps the existing codes when only a recent grant exists" do
        post new_user_webauthn_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo
        expect(session.dig("authn_context", "mfa_time")).to be_present

        expect { post regenerate_backup_user_totp_credential_path, headers: turbo }
          .not_to(change { totp_credential.reload.otp_backup_codes })
      end
    end
  end
end
