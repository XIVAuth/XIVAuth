require "rails_helper"

# App and team deletion: users with MFA confirm via sudo mode, everyone else by typing the name (checked server-side).
RSpec.describe "Developer destroy confirmations" do
  # The :developer trait enables TOTP, but the portal doesn't require MFA.
  let(:user) { FactoryBot.create(:user, roles: ["developer"]) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }
  let(:totp_secret) { ROTP::Base32.random }

  before { sign_in user }

  def valid_otp
    ROTP::TOTP.new(totp_secret).now
  end

  def enable_mfa
    FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
    user.reload
  end

  shared_examples "a confirmed destroy" do
    context "when the user has no MFA" do
      it "opens the modal with the typed-name confirmation" do
        expect { delete path, headers: turbo }.not_to change(model, :count)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(modal_id).and include("confirm_text")
        expect(response.body).not_to include("sudo[otp_attempt]")
      end

      it "re-renders the modal with an error when the name doesn't match" do
        expect { delete path, params: { confirm_text: "nope" }, headers: turbo }.not_to change(model, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("#{modal_id}-content").and include("didn&#39;t match")
      end

      it "rejects a plain HTML request without the name" do
        expect { delete path }.not_to change(model, :count)
        expect(flash[:alert]).to be_present
      end

      it "deletes when the name matches" do
        expect { delete path, params: { confirm_text: record.name }, headers: turbo }.to change(model, :count).by(-1)
      end
    end

    context "when the user has MFA" do
      before { enable_mfa }

      it "opens the modal with the MFA challenge instead of the name" do
        expect { delete path, headers: turbo }.not_to change(model, :count)

        expect(response.body).to include(modal_id).and include("sudo[otp_attempt]")
        expect(response.body).not_to include('name="confirm_text"')
      end

      it "does not accept the typed name instead of MFA" do
        expect { delete path, params: { confirm_text: record.name }, headers: turbo }.not_to change(model, :count)
      end

      it "re-renders the modal with an error for a bad code" do
        expect { delete path, params: { sudo: { otp_attempt: "000000" } }, headers: turbo }.not_to change(model, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("#{modal_id}-content")
      end

      it "deletes with a valid code" do
        expect { delete path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo }
          .to change(model, :count).by(-1)
      end

      it "requires a fresh code even with a recent MFA proof" do
        post new_user_webauthn_credential_path, params: { sudo: { otp_attempt: valid_otp } }, headers: turbo

        expect { delete path, headers: turbo }.not_to change(model, :count)
      end
    end

    it "denies users who can't delete it, without prompting for MFA" do
      sign_in FactoryBot.create(:user, :developer)

      expect { delete path, headers: turbo }.to raise_error(denied_error)
    end
  end

  describe "DELETE /developer/applications/:id" do
    # Team-owned, since user-owned apps require an MFA-protected owner at creation.
    let!(:record) do
      team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :developer, team: team, user: user)
      FactoryBot.create(:client_application, owner: team)
    end
    let(:model) { ClientApplication }
    let(:path) { developer_application_path(record) }
    let(:modal_id) { "delete_app_modal" }
    let(:denied_error) { ActiveRecord::RecordNotFound } # apps hide themselves from users who can't see them

    it_behaves_like "a confirmed destroy"
  end

  describe "DELETE /developer/teams/:id" do
    let!(:record) do
      FactoryBot.build(:team, :no_initial_admin, name: "Test Team").tap do |team|
        team.direct_memberships.build(user: user, role: "admin")
        team.save!
      end
    end
    let(:model) { Team }
    let(:path) { developer_team_path(record) }
    let(:modal_id) { "delete_team_modal" }
    let(:denied_error) { CanCan::AccessDenied }

    it_behaves_like "a confirmed destroy"
  end
end
