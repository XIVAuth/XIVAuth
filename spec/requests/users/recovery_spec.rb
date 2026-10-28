require "rails_helper"

RSpec.describe "Users::RecoveryController" do
  describe "POST /auth/recovery" do
    let(:reset_subject) { I18n.t("devise.mailer.reset_password_instructions.subject") }
    let(:confirmation_subject) { I18n.t("devise.mailer.confirmation_instructions.subject") }

    before do
      allow_any_instance_of(Users::RecoveryController).to receive(:cloudflare_turnstile_ok?).and_return(true)
      ActionMailer::Base.deliveries.clear
    end

    def recover(email)
      post user_recovery_path, params: { user: { email: email } }
    end

    def sent_subjects
      ActionMailer::Base.deliveries.map(&:subject)
    end

    context "when the user is confirmed" do
      let!(:user) { FactoryBot.create(:user, email: "recovery-user@example.test") }

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

      it "sends only a password reset email to the user" do
        recover(user.email)

        expect(sent_subjects).to eq([reset_subject])
        expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to eq(Users::RecoveryController::RECOVERY_MESSAGE)
      end

      it "does not touch the confirmation state" do
        expect { recover(user.email) }.not_to(change { user.reload.attributes.slice("confirmation_token", "confirmed_at") })
      end

      context "with a pending email change" do
        before do
          user.update!(email: "new-address@example.test")
          ActionMailer::Base.deliveries.clear
        end

        it "sends a password reset to the current address, not a reconfirmation" do
          expect(user.reload.unconfirmed_email).to eq("new-address@example.test")

          recover("recovery-user@example.test")

          expect(sent_subjects).to eq([reset_subject])
          expect(ActionMailer::Base.deliveries.last.to).to eq(["recovery-user@example.test"])
        end

        it "does not match on the unconfirmed address" do
          recover("new-address@example.test")

          expect(sent_subjects).to be_empty
          expect(user.reload.reset_password_token).to be_nil
        end
      end
    end

    context "when the user is unconfirmed" do
      let!(:user) { FactoryBot.create(:user, email: "unconfirmed-user@example.test", confirmed_at: nil) }

      before { ActionMailer::Base.deliveries.clear }

      it "resends confirmation instructions instead of a password reset" do
        recover(user.email)

        expect(sent_subjects).to eq([confirmation_subject])
        expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
        expect(user.reload.reset_password_token).to be_nil
      end

      it "matches the email case-insensitively" do
        recover("Unconfirmed-User@EXAMPLE.test")

        expect(sent_subjects).to eq([confirmation_subject])
      end

      it "leaves the user unconfirmed" do
        recover(user.email)

        expect(user.reload.confirmed?).to be(false)
      end

      it "shows the same generic message as for confirmed users" do
        recover(user.email)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to eq(Users::RecoveryController::RECOVERY_MESSAGE)
      end
    end

    context "when no user has the email" do
      it "sends nothing and shows the same generic message" do
        recover("nobody@example.test")

        expect(sent_subjects).to be_empty
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to eq(Users::RecoveryController::RECOVERY_MESSAGE)
      end
    end

    context "when the email is blank" do
      it "re-renders the form without sending anything" do
        recover("")

        expect(response).to have_http_status(:unprocessable_content)
        expect(sent_subjects).to be_empty
      end
    end
  end
end
