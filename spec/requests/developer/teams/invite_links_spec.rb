require "rails_helper"

RSpec.describe "Developer::Teams::InviteLinks" do
  let(:user) { FactoryBot.create(:user) }
  let(:team) { FactoryBot.create(:team) }

  before { sign_in user }

  describe "GET /developer/teams/join/:code" do
    it "creates the requested membership and consumes one use" do
      invite_link = Team::InviteLink.create!(team: team, target_role: "developer", usage_limit: 2)

      expect do
        get "/developer/teams/join/#{invite_link.invite_key}"
      end.to change { Team::Membership.where(team: team, user: user).count }.by(1)

      expect(Team::Membership.find_by!(team: team, user: user).role).to eq("developer")
      expect(invite_link.reload.usage_count).to eq(1)
      expect(response).to redirect_to(developer_team_path(team))
    end

    it "rejects disabled, expired, and exhausted invite links" do
      disabled = Team::InviteLink.create!(team: team, target_role: "member", enabled: false)
      expired = Team::InviteLink.create!(team: team, target_role: "member", expires_at: 5.minutes.from_now)
      expired.update_column(:expires_at, 1.minute.ago)
      exhausted = Team::InviteLink.create!(
        team: team,
        target_role: "member",
        usage_limit: 1,
        usage_count: 1
      )

      [disabled, expired, exhausted].each do |invite_link|
        expect do
          get "/developer/teams/join/#{invite_link.invite_key}"
        end.not_to change { Team::Membership.where(team: team, user: user).count }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Team invite link invalid.")
      end
    end

    it "rejects later users after consuming the final use" do
      invite_link = Team::InviteLink.create!(team: team, target_role: "member", usage_limit: 1)

      get "/developer/teams/join/#{invite_link.invite_key}"

      second_user = FactoryBot.create(:user)
      sign_in second_user

      expect do
        get "/developer/teams/join/#{invite_link.invite_key}"
      end.not_to change { Team::Membership.where(team: team, user: second_user).count }

      expect(invite_link.reload.usage_count).to eq(1)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Team invite link invalid.")
    end

    it "rejects an unknown invite code without attempting membership creation" do
      expect do
        get "/developer/teams/join/not-a-real-invite"
      end.not_to change(Team::Membership, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Team invite link invalid.")
    end
  end
end
