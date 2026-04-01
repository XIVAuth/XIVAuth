require "rails_helper"
require "support/authentication_helpers"

RSpec.describe "Users::RegistrationsController", type: :request do
  include AuthenticationHelpers
  include Warden::Test::Helpers

  let(:password) { "SecurePassword123!" }

  before do
    allow_any_instance_of(Users::RegistrationsController).to receive(:cloudflare_turnstile_ok?).and_return(true)
  end

  after do
    Warden.test_reset!
  end

  describe "POST /auth/register (sign up)" do
    before do
      Flipper.enable(:user_signups)
    end

    context "when the email domain does not resolve" do
      before do
        allow_any_instance_of(EmailValidator).to receive(:reachable?).and_return(false)
      end

      it "rejects the registration and sends no email" do
        expect {
          post user_registration_path, params: { user: {
            email: "user@example.ocm",
            password: password,
            password_confirmation: password
          }}
        }.not_to change(ActionMailer::Base.deliveries, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PUT /profile (account update)" do
    context "when user is passwordless" do
      let(:user) { FactoryBot.create(:user, :passwordless) }

      before do
        login_as(user, scope: :user)
      end

      it "allows updating email without a password" do
        new_email = "passwordless-new@example.test"

        patch edit_user_path, params: { user: { email: new_email } }

        expect(response).to redirect_to(edit_user_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)

        user.reload
        expect(user.unconfirmed_email).to eq(new_email)
      end

      it "allows updating password for a passwordless user" do
        new_password = "NewPassword1!"

        patch edit_user_path, params: { user: {
          password: new_password,
          password_confirmation: new_password
        }}

        expect(response).to redirect_to(edit_user_path)

        # Verify the new password was saved.
        user.reload
        expect(user.valid_password?(new_password)).to be_truthy
        expect(user.has_password?).to be_truthy
      end
    end

    context "when user has a password" do
      let(:user) { FactoryBot.create(:user, password: password, password_confirmation: password) }

      before do
        login_as(user, scope: :user)
      end

      it "allows updating display_name without providing current_password" do
        new_name = "FriendlyName"

        patch edit_user_path, params: { user: { profile_attributes: { display_name: new_name } } }

        expect(response).to redirect_to(edit_user_path)

        follow_redirect!
        expect(response).to have_http_status(:ok)

        user.reload
        expect(user.profile.display_name).to eq(new_name)
      end

      it "does not allow changing email without current_password" do
        old_email = user.email
        patch edit_user_path, params: { user: { email: "new-email@example.test" } }

        # Devise should re-render the edit page with an error when current_password is missing/incorrect
        expect(response).to have_http_status(:unprocessable_content)

        user.reload
        expect(user.email).to eq(old_email)
        expect(user.unconfirmed_email).to be_nil
      end

      it "does not allow changing password without current_password" do
        new_password = "AnotherNew1!"

        patch edit_user_path, params: { user: { password: new_password, password_confirmation: new_password } }

        expect(response).to have_http_status(:unprocessable_content)

        user.reload
        expect(user.valid_password?(new_password)).to be_falsey
      end

      it "accepts current_password when provided and updates protected fields" do
        old_email = user.email
        new_email = "changed@example.test"
        patch edit_user_path, params: { user: { email: new_email, current_password: password } }

        expect(response).to redirect_to(edit_user_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)

        user.reload
        expect(user.email).to eq(old_email)
        expect(user.unconfirmed_email).to eq(new_email)
      end

      it "validates the current_password when one is provided" do
        patch edit_user_path, params: { user: {
          current_password: "ACompletelyIncorrectPassword!",
          profile_attributes: { display_name: "new_test_name" } }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
