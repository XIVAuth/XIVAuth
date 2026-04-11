require "rails_helper"
require "support/authentication_helpers"
require "webauthn/fake_client"

RSpec.describe "Users::SessionsController", type: :request do
  let(:password) { "SecurePassword123!" }
  let(:user) {
    FactoryBot.create(:user, password: password, password_confirmation: password,
                      webauthn_id: WebAuthn.generate_user_id)
  }
  let(:origin) { "http://localhost:3000" }
  let(:rp_id) { URI.parse(origin).host }

  before do
    # Mock Cloudflare Turnstile to always pass
    allow_any_instance_of(Users::SessionsController).to receive(:cloudflare_turnstile_ok?).and_return(true)
  end

  # Helper methods
  def login_params(email: user.email, password: self.password, **extra_params)
    { user: { email: email, password: password, **extra_params } }
  end

  def mfa_params(otp_attempt: nil, webauthn_response: nil)
    { mfa: { otp_attempt: otp_attempt, webauthn_response: webauthn_response }.compact }
  end

  def generate_discoverable_challenge
    get new_user_session_path
    session["webauthn_discoverable_challenge"]
  end

  def create_webauthn_credential_for_user(user, fake_client)
    create_options = WebAuthn::Credential.options_for_create(
      user: { id: user.webauthn_id, name: user.email }
    )

    fake_response = fake_client.create(challenge: create_options.challenge)
    recovered_data = WebAuthn::Credential.from_create(fake_response)

    FactoryBot.create(:users_webauthn_credential,
                      user: user,
                      external_id: recovered_data.id,
                      public_key: recovered_data.public_key,
                      sign_count: 0
    )
  end

  describe "GET /users/sign_in" do
    it "renders the sign in page" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sign")
    end

    it "generates a discoverable WebAuthn challenge" do
      get new_user_session_path
      expect(session["webauthn_discoverable_challenge"]).to be_present
    end
  end

  describe "POST /users/sign_in - Standard Login" do
    context "with valid credentials" do
      it "signs in the user successfully" do
        post user_session_path, params: login_params

        expect(response).to redirect_to(character_registrations_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "clears any password reset tokens" do
        user.update(reset_password_token: "some_token", reset_password_sent_at: Time.current)

        post user_session_path, params: login_params

        user.reload
        expect(user.reset_password_token).to be_nil
        expect(user.reset_password_sent_at).to be_nil
      end
    end

    context "with invalid credentials" do
      it "fails to sign in with wrong password" do
        post user_session_path, params: login_params(password: "WrongPassword123!")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid email or password.")
      end

      it "fails to sign in with non-existent email" do
        post user_session_path, params: login_params(email: "nonexistent@example.test")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid email or password.")
      end
    end

    context "with failed captcha" do
      before do
        allow_any_instance_of(Users::SessionsController).to receive(:cloudflare_turnstile_ok?).and_return(false)
      end

      it "rejects the login attempt" do
        post user_session_path, params: login_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("CAPTCHA")
      end
    end

    context "with remember me" do
      it "sets remember me cookie when requested" do
        post user_session_path, params: login_params(remember_me: "1")

        expect(response.cookies["remember_user_token"]).to be_present
      end
    end
  end

  describe "POST /users/sign_in - MFA Flow with TOTP" do
    let(:totp_secret) { ROTP::Base32.random }
    let(:totp_credential) do
      FactoryBot.create(:users_totp_credential,
                        user: user,
                        otp_secret: totp_secret,
                        otp_enabled: true
      )
    end
    let(:valid_otp) { ROTP::TOTP.new(totp_secret).now }

    context "MFA challenge with TOTP" do
      before do
        totp_credential # Ensure credential exists
        # Simulate initial login that triggered MFA
        post user_session_path, params: login_params
      end

      it "signs in with valid TOTP code" do
        post user_session_path, params: mfa_params(otp_attempt: valid_otp)

        expect(response).to redirect_to(character_registrations_path)
        expect(session["mfa"]).to be_nil
      end

      it "rejects invalid TOTP code" do
        post user_session_path, params: mfa_params(otp_attempt: "000000")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("invalid") | include("failed")
        expect(session["mfa"]).to be_present
      end

      it "accepts valid backup code" do
        backup_codes = totp_credential.generate_otp_backup_codes!
        totp_credential.save!

        post user_session_path, params: mfa_params(otp_attempt: backup_codes.first)

        expect(response).to redirect_to(character_registrations_path)
        expect(session["mfa"]).to be_nil

        # Verify backup code was consumed
        totp_credential.reload
        expect(totp_credential.otp_backup_codes.count).to be(4)
      end
    end
  end

  describe "POST /users/sign_in - MFA Flow with WebAuthn" do
    let(:fake_client) { WebAuthn::FakeClient.new(origin, encoding: :base64url) }
    let!(:webauthn_credential) { create_webauthn_credential_for_user(user, fake_client) }

    context "initial login with valid password" do
      it "prompts for MFA with WebAuthn challenge" do
        post user_session_path, params: login_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(session["mfa"]).to be_present
        expect(session["mfa"]["webauthn_challenge"]).to be_present
      end
    end

    context "MFA challenge with WebAuthn" do
      before do
        # Simulate initial login that triggered MFA
        post user_session_path, params: login_params
      end

      it "signs in with valid WebAuthn response" do
        challenge = session["mfa"]["webauthn_challenge"]

        assertion_response = fake_client.get(challenge: challenge, sign_count: webauthn_credential.sign_count + 1)

        post user_session_path, params: mfa_params(webauthn_response: assertion_response.to_json)

        expect(response).to redirect_to(character_registrations_path)
        expect(session["mfa"]).to be_nil

        # Verify sign count was updated
        webauthn_credential.reload
        expect(webauthn_credential.sign_count).to be > 0
      end

      it "rejects invalid WebAuthn response with wrong challenge" do
        # Use a different challenge than what's in the session
        wrong_challenge = Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)

        assertion_response = fake_client.get(challenge: wrong_challenge)

        post user_session_path, params: mfa_params(webauthn_response: assertion_response.to_json)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("failed") | include("WebAuthn")
        expect(session["mfa"]).to be_present
      end

      it "rejects WebAuthn response with invalid sign count" do
        challenge = session["mfa"]["webauthn_challenge"]
        webauthn_credential.update!(sign_count: 100)

        assertion_response = fake_client.get(challenge: challenge, sign_count: 50)

        post user_session_path, params: mfa_params(webauthn_response: assertion_response.to_json)

        expect(response).to have_http_status(:unprocessable_content)
        expect(session["mfa"]).to be_present
      end
    end
  end

  describe "POST /users/sign_in - Passkey (Discoverable Credential) Flow" do
    let(:fake_client) { WebAuthn::FakeClient.new(origin, encoding: :base64url) }
    let!(:webauthn_credential) { create_webauthn_credential_for_user(user, fake_client) }
    let!(:challenge) { generate_discoverable_challenge }

    it "signs in directly with passkey without password" do
      assertion_response = fake_client.get(
        challenge: challenge,
        user_handle: Base64.urlsafe_decode64(user.webauthn_id),
        sign_count: webauthn_credential.sign_count + 1,
        user_verified: true
      )

      post user_session_path, params: { user: { webauthn_response: assertion_response.to_json } }

      expect(response).to redirect_to(character_registrations_path)
      expect(session["webauthn_discoverable_challenge"]).to be_nil
    end

    it "rejects passkeys not asserting user_verified (CVE-2020-8236)" do
      # Generate a valid discoverable credential assertion
      assertion_response = fake_client.get(
        challenge: challenge,
        user_handle: Base64.urlsafe_decode64(user.webauthn_id),
        sign_count: webauthn_credential.sign_count + 1,
        user_verified: false
      )

      post user_session_path, params: { user: { webauthn_response: assertion_response.to_json } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("WebAuthn::UserVerifiedVerificationError")
    end

    it "rejects passkey with wrong challenge" do
      # Use a different challenge
      wrong_challenge = Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)

      assertion_response = fake_client.get(
        challenge: wrong_challenge,
        user_handle: Base64.urlsafe_decode64(user.webauthn_id),
        )

      post user_session_path, params: {
        user: {
          webauthn_response: assertion_response.to_json
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("WebAuthn::ChallengeVerificationError")
    end

    it "rejects an unregistered passkey with a valid user_handle" do
      evil_client = build_fake_webauthn(origin)

      assertion_response = evil_client.get(
        challenge: challenge,
        user_handle: Base64.urlsafe_decode64(user.webauthn_id),
        sign_count: 0,
        user_verified: true
      )

      post user_session_path, params: { user: { webauthn_response: assertion_response.to_json } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Security key presented is not registered.")
    end

    it "rejects an unregistered passkey" do
      unregistered_client = build_fake_webauthn(origin)

      assertion_response =  unregistered_client.get(
        challenge: challenge,
        user_handle: "A_Fake_User_Handle",
        sign_count: 0,
        user_verified: true
      )

      post user_session_path, params: { user: { webauthn_response: assertion_response.to_json } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Security key presented is not registered.")
    end

    it "ignores a passed email address if a passkey is present" do
      secondary_user = FactoryBot.create(:user)

      assertion_response = fake_client.get(
        challenge: challenge,
        user_handle: Base64.urlsafe_decode64(user.webauthn_id),
        sign_count: webauthn_credential.sign_count + 1,
        user_verified: true
      )

      post user_session_path, params: { user: {
        webauthn_response: assertion_response.to_json,
        email: secondary_user.email
      } }

      expect(response).to redirect_to(character_registrations_path)
      expect(session["webauthn_discoverable_challenge"]).to be_nil

      expect(controller.current_user).to eq(user)
    end
  end

  describe "DELETE /users/sign_out" do
    before do
      true_sign_in user, password: password
    end

    it "signs out the user successfully" do
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /profile/other_sessions" do
    let(:other_private_id) { SecureRandom.urlsafe_base64(32) }
    let(:other_session) { { sid: other_private_id, expires_at: 7.days.from_now } }

    before do
      true_sign_in user, password: password
      allow_any_instance_of(User).to receive(:get_sessions).and_return([other_session])
      allow_any_instance_of(User).to receive(:destroy_sessions)
    end

    context "without confirmed param (first DELETE - turbo stream modal)" do
      it "renders a turbo stream response" do
        delete other_sessions_user_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "includes the session count in the response body" do
        delete other_sessions_user_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("1")
      end

      it "does not destroy any sessions" do
        expect_any_instance_of(User).not_to receive(:destroy_sessions)
        delete other_sessions_user_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    context "with confirmed param (second DELETE - actual destruction)" do
      it "destroys the other sessions" do
        expect_any_instance_of(User).to receive(:destroy_sessions).with([other_private_id])
        delete other_sessions_user_path, params: { confirmed: "1" }
      end

      it "redirects to the profile edit page" do
        delete other_sessions_user_path, params: { confirmed: "1" }
        expect(response).to redirect_to(edit_user_path)
      end

      it "sets a flash notice with the session count" do
        delete other_sessions_user_path, params: { confirmed: "1" }
        follow_redirect!
        expect(response.body).to include("other session")
      end

      it "does not destroy the current session" do
        delete other_sessions_user_path, params: { confirmed: "1" }

        # try going to a random page and see if it still works.
        get character_registrations_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "Redirect after login" do
    context "with stored location" do
      it "redirects to stored location after successful login" do
        stored_location = developer_applications_path

        get stored_location
        expect(response).to redirect_to(new_user_session_path)

        post user_session_path, params: login_params

        expect(response).to redirect_to(stored_location)
      end
    end

    context "without stored location" do
      it "redirects to character registrations path" do
        post user_session_path, params: login_params
        expect(response).to redirect_to(character_registrations_path)
      end
    end
  end
end
