require "rails_helper"

RSpec.describe Users::RequiresSudo, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  controller(ApplicationController) do
    include Users::RequiresSudo

    requires_sudo only: :destroy, within: 0, and_rerender: :render_challenge
    requires_sudo only: :update, within: 1.hour, and_rerender: :render_challenge

    def update
      render plain: "updated"
    end

    def destroy
      render plain: "destroyed (sudo_verified: #{sudo_verified?})"
    end

    private def render_challenge(error: nil)
      render plain: "challenge: #{error}", status: error ? :unprocessable_content : :ok
    end
  end

  let(:user) { FactoryBot.create(:user) }
  let(:totp_secret) { ROTP::Base32.random }

  before do
    routes.draw do
      patch "update" => "anonymous#update"
      delete "destroy" => "anonymous#destroy"
    end

    sign_in user
  end

  def valid_otp
    ROTP::TOTP.new(totp_secret).now
  end

  context "when the user has no MFA" do
    it "passes through without sudo_verified?, leaving confirmation to the action" do
      delete :destroy
      expect(response.body).to eq("destroyed (sudo_verified: false)")
    end
  end

  context "when the user has TOTP enabled" do
    before do
      FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
      user.reload
    end

    it "challenges when no proof is given" do
      patch :update
      expect(response.body).to eq("challenge: ")
    end

    it "challenges even when the action's own confirmation is sent" do
      delete :destroy, params: { confirm_text: "anything" }
      expect(response.body).to eq("challenge: ")
    end

    it "allows the action with a valid proof and records a grant" do
      patch :update, params: { sudo: { otp_attempt: valid_otp } }

      expect(response.body).to eq("updated")
      expect(session["authn_context"]["amr"]).to include("otp", "mfa")
    end

    it "re-challenges with an error for an invalid proof" do
      patch :update, params: { sudo: { otp_attempt: "000000" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/TOTP/)
    end

    it "accepts a fresh grant within the window" do
      Users::AuthnContext.new(session).record_step_up!(:totp)

      patch :update
      expect(response.body).to eq("updated")
    end

    it "rejects a grant older than the window" do
      travel_to(2.hours.ago) { Users::AuthnContext.new(session).record_step_up!(:totp) }

      patch :update
      expect(response.body).to eq("challenge: ")
    end

    it "always requires proof for a zero window" do
      Users::AuthnContext.new(session).record_step_up!(:totp)

      delete :destroy
      expect(response.body).to eq("challenge: ")

      delete :destroy, params: { sudo: { otp_attempt: valid_otp } }
      expect(response.body).to eq("destroyed (sudo_verified: true)")
    end

    it "locks out after repeated failures" do
      Users::StepUpLockout::MAX_FAILURES.times { Users::StepUpLockout.new(session).record_failure! }

      patch :update, params: { sudo: { otp_attempt: valid_otp } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/Too many/)
    end

    it "re-prompts with an error when the challenge is submitted empty" do
      patch :update, params: { sudo: { prompted: "1" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/security key or enter a code/)
    end
  end
end
