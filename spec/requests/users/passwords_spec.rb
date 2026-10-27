require "rails_helper"

RSpec.describe "Users::PasswordsController" do
  let(:old_password) { "OldPassword123!" }
  let(:new_password) { "NewSecurePassword456!" }
  let(:user) { FactoryBot.create(:user, password: old_password, password_confirmation: old_password) }

  def reset_password!(token:)
    put reset_user_password_path, params: {
      user: { reset_password_token: token, password: new_password, password_confirmation: new_password }
    }
  end

  def signed_in?
    get character_registrations_path
    response.status == 200
  end

  describe "PUT /auth/recovery/password" do
    let(:token) { user.send_reset_password_instructions }

    context "when the user has no MFA" do
      it "changes the password and signs the user in" do
        reset_password!(token: token)

        expect(user.reload.valid_password?(new_password)).to be(true)
        expect(response).to redirect_to(user_session_path)
        expect(signed_in?).to be(true)
      end
    end

    context "when the user has TOTP enabled" do
      before { FactoryBot.create(:users_totp_credential, :enabled, user: user) }

      it "changes the password but does not sign the user in" do
        reset_password!(token: token)

        expect(user.reload.valid_password?(new_password)).to be(true)
        expect(response).to redirect_to(user_session_path)
        expect(signed_in?).to be(false)
      end
    end

    context "when the user has a WebAuthn credential" do
      before { FactoryBot.create(:users_webauthn_credential, user: user) }

      it "changes the password but does not sign the user in" do
        reset_password!(token: token)

        expect(user.reload.valid_password?(new_password)).to be(true)
        expect(response).to redirect_to(user_session_path)
        expect(signed_in?).to be(false)
      end
    end

    context "when the reset token is invalid" do
      it "does not change the password or sign the user in" do
        reset_password!(token: "not-a-real-token")

        expect(user.reload.valid_password?(old_password)).to be(true)
        expect(signed_in?).to be(false)
      end
    end
  end
end
