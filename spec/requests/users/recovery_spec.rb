require "rails_helper"

RSpec.describe "Users::RecoveryController" do
  describe "POST /auth/recovery" do
    let!(:user) { FactoryBot.create(:user, email: "recovery-user@example.test") }

    before do
      allow_any_instance_of(Users::RecoveryController).to receive(:cloudflare_turnstile_ok?).and_return(true)
    end

    def recover(email)
      post user_recovery_path, params: { user: { email: email } }
    end

    it "sends reset instructions for an exact email match" do
      expect { recover("recovery-user@example.test") }
        .to change { user.reload.reset_password_token }.from(nil)
    end

    it "matches the email case-insensitively" do
      expect { recover("Recovery-User@EXAMPLE.test") }
        .to change { user.reload.reset_password_token }.from(nil)
    end

    it "ignores surrounding whitespace in the email" do
      expect { recover("  recovery-user@example.test  ") }
        .to change { user.reload.reset_password_token }.from(nil)
    end
  end
end
