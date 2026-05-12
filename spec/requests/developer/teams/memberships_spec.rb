require "rails_helper"

RSpec.describe "Developer::Teams::Memberships" do
  let(:user) { FactoryBot.create(:user, :developer) }
  let(:target_user) { FactoryBot.create(:user) }

  # Build a root team owned by another admin so `user` can be given any role.
  let!(:team) do
    team = FactoryBot.build(:team, :no_initial_admin, name: "Test Team")
    team.direct_memberships.build(user: FactoryBot.create(:user), role: "admin")
    team.save!
    team
  end

  let!(:target_membership) do
    FactoryBot.create(:team_membership, team: team, user: target_user, role: "member")
  end

  before { sign_in user }

  describe "PATCH /developer/teams/:team_id/memberships/:user_id (update)" do
    context "as an admin" do
      before { FactoryBot.create(:team_membership, :admin, team: team, user: user) }

      it "can promote a member to admin" do
        patch developer_team_membership_path(team, target_user),
              params: { team_membership: { role: "admin" } }

        expect(target_membership.reload.role).to eq("admin")
      end

      it "can promote a member to manager" do
        patch developer_team_membership_path(team, target_user),
              params: { team_membership: { role: "manager" } }

        expect(target_membership.reload.role).to eq("manager")
      end
    end

    context "as a manager" do
      before { FactoryBot.create(:team_membership, :manager, team: team, user: user) }

      it "can change a member to developer" do
        patch developer_team_membership_path(team, target_user),
              params: { team_membership: { role: "developer" } }

        expect(target_membership.reload.role).to eq("developer")
      end

      it "cannot promote a member to admin" do
        patch developer_team_membership_path(team, target_user),
              params: { team_membership: { role: "admin" } }

        # Role should be unchanged — the param is stripped by membership_params
        expect(target_membership.reload.role).to eq("member")
      end

      it "cannot promote a member to manager" do
        patch developer_team_membership_path(team, target_user),
              params: { team_membership: { role: "manager" } }

        expect(target_membership.reload.role).to eq("member")
      end

      it "cannot change the role of an existing admin" do
        admin_user = FactoryBot.create(:user)
        FactoryBot.create(:team_membership, :admin, team: team, user: admin_user)

        patch developer_team_membership_path(team, admin_user),
              params: { team_membership: { role: "member" } }

        expect(response).to redirect_to(developer_team_path(team))
        expect(flash[:alert]).to match(/managers cannot/i)
      end

      it "cannot change the role of another manager" do
        other_manager = FactoryBot.create(:user)
        FactoryBot.create(:team_membership, :manager, team: team, user: other_manager)

        patch developer_team_membership_path(team, other_manager),
              params: { team_membership: { role: "member" } }

        expect(response).to redirect_to(developer_team_path(team))
        expect(flash[:alert]).to match(/managers cannot/i)
      end
    end

    context "as a developer" do
      before { FactoryBot.create(:team_membership, :developer, team: team, user: user) }

      it "is denied access" do
        expect do
          patch developer_team_membership_path(team, target_user),
                params: { team_membership: { role: "developer" } }
        end.to raise_error(CanCan::AccessDenied)
      end
    end

    context "as a member" do
      before { FactoryBot.create(:team_membership, team: team, user: user) }

      it "is denied access" do
        expect do
          patch developer_team_membership_path(team, target_user),
                params: { team_membership: { role: "developer" } }
        end.to raise_error(CanCan::AccessDenied)
      end
    end
  end

  describe "DELETE /developer/teams/:team_id/memberships/:user_id (destroy)" do
    context "as an admin" do
      before { FactoryBot.create(:team_membership, :admin, team: team, user: user) }

      it "can remove a member" do
        expect do
          delete developer_team_membership_path(team, target_user), params: { commit: "1" }
        end.to change(Team::Membership, :count).by(-1)
      end

      it "cannot remove themselves" do
        delete developer_team_membership_path(team, user), params: { commit: "1" }

        expect(response).to redirect_to(developer_team_path(team))
        expect(flash[:alert]).to match(/cannot remove yourself/i)
      end
    end

    context "as a manager" do
      before { FactoryBot.create(:team_membership, :manager, team: team, user: user) }

      it "can remove a regular member" do
        expect do
          delete developer_team_membership_path(team, target_user), params: { commit: "1" }
        end.to change(Team::Membership, :count).by(-1)
      end

      it "cannot remove an admin" do
        admin_user = FactoryBot.create(:user)
        FactoryBot.create(:team_membership, :admin, team: team, user: admin_user)

        delete developer_team_membership_path(team, admin_user), params: { commit: "1" }

        expect(response).to redirect_to(developer_team_path(team))
        expect(flash[:alert]).to match(/managers cannot/i)
      end

      it "cannot remove another manager" do
        other_manager = FactoryBot.create(:user)
        FactoryBot.create(:team_membership, :manager, team: team, user: other_manager)

        delete developer_team_membership_path(team, other_manager), params: { commit: "1" }

        expect(response).to redirect_to(developer_team_path(team))
        expect(flash[:alert]).to match(/managers cannot/i)
      end
    end

    context "as a developer" do
      before { FactoryBot.create(:team_membership, :developer, team: team, user: user) }

      it "is denied access" do
        expect do
          delete developer_team_membership_path(team, target_user), params: { commit: "1" }
        end.to raise_error(CanCan::AccessDenied)
      end
    end
  end
end
