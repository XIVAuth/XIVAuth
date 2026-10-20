require "rails_helper"

RSpec.describe "Email delivery failures during signup and recovery" do
  let(:password) { "SecurePassword123!" }

  def fail_deliveries_with(error)
    @delivery_attempts = 0
    allow_any_instance_of(Mail::TestMailer).to receive(:deliver!) do
      @delivery_attempts += 1
      raise error
    end
  end

  def inactive_recipient_error
    Postmark::ApiInputError.build("inactive", { "ErrorCode" => 406 })
  end

  before do
    allow(Sentry).to receive(:capture_exception)
  end

  describe "POST /auth/register" do
    let(:email) { "new-user@example.test" }

    before do
      Flipper.enable(:user_signups)
      allow_any_instance_of(Users::RegistrationsController).to receive(:cloudflare_turnstile_ok?).and_return(true)
      allow_any_instance_of(EmailValidator).to receive(:reachable?).and_return(true)
    end

    def sign_up
      post user_registration_path, params: { user: {
        email: email,
        password: password,
        password_confirmation: password,
        profile_attributes: { display_name: "New User" }
      } }
    end

    it "removes the account when the recipient is rejected" do
      fail_deliveries_with(inactive_recipient_error)

      expect { sign_up }.not_to change(User, :count)
      expect(@delivery_attempts).to eq(1)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("rejected the email address")
    end

    it "keeps the account and points the user at recovery when delivery fails" do
      fail_deliveries_with(Postmark::TimeoutError.new("timed out"))

      expect { sign_up }.to change(User, :count).by(1)
      expect(@delivery_attempts).to eq(1)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:error]).to include("account recovery")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(EmailDelivery::Failed))
    end
  end

  describe "POST /auth/recovery" do
    let!(:user) { FactoryBot.create(:user) }

    before do
      allow_any_instance_of(Users::RecoveryController).to receive(:cloudflare_turnstile_ok?).and_return(true)
    end

    def recover
      post user_recovery_path, params: { user: { email: user.email } }
    end

    it "shows the provider rejection message when the recipient is rejected" do
      fail_deliveries_with(inactive_recipient_error)

      recover

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("rejected the email address")
    end

    it "asks the user to try again later when delivery fails" do
      fail_deliveries_with(Postmark::TimeoutError.new("timed out"))

      recover

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("try again in a few minutes")
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(EmailDelivery::Failed))
    end
  end
end
