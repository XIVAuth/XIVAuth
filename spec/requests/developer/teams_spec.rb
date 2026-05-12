require "rails_helper"

RSpec.describe "Developer::Teams", type: :request do
  let(:user) { FactoryBot.create(:user, :developer) }
  let(:other_user) { FactoryBot.create(:user, :developer) }

  before do
    sign_in user
  end

  describe "POST /developer/teams (create)" do
    context "when creating a standalone team" do
      it "creates a team and makes the user an admin" do
        expect do
          post developer_teams_path, params: { team: { name: "My Team" } }
        end.to change(Team, :count).by(1)

        team = Team.last
        expect(team.name).to eq("My Team")
        expect(team.parent_id).to be_nil
        expect(team.direct_memberships.where(user: user, role: "admin")).to exist
      end

      it "requires a team name" do
        post developer_teams_path, params: { team: { name: "" } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "automatically builds a profile" do
        post developer_teams_path, params: { team: { name: "My Team" } }

        team = Team.last
        expect(team.profile).to be_present
      end
    end

    context "when creating a subteam" do
      let!(:parent_team) do
        team = FactoryBot.build(:team, :no_initial_admin, name: "Parent Team")
        team.direct_memberships.build(user: user, role: "admin")
        team.save!
        team
      end

      it "creates a subteam when user is an admin of the parent" do
        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: parent_team.id } }
        end.to change(Team, :count).by(1)

        team = Team.last
        expect(team.name).to eq("Child Team")
        expect(team.parent_id).to eq(parent_team.id)
      end

      it "does not add the user as an admin to the subteam" do
        post developer_teams_path, params: { team: { name: "Child Team", parent_id: parent_team.id } }

        team = Team.last
        expect(team.direct_memberships.where(user: user, role: "admin")).not_to exist
      end

      it "prevents creating a subteam when user is not an admin of the parent" do
        non_admin_team = FactoryBot.create(:team)
        # User is not a member at all

        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: non_admin_team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "prevents creating a subteam when user is only a member (not admin) of the parent" do
        member_team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, team: member_team, user: user, role: "member")

        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: member_team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "prevents creating a subteam when user is a developer (not admin) of the parent" do
        dev_team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :developer, team: dev_team, user: user)

        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: dev_team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "allows creating a subteam when user is an admin via antecedent team" do
        grandparent = FactoryBot.build(:team, :no_initial_admin, name: "Grandparent")
        grandparent.direct_memberships.build(user: user, role: "admin")
        grandparent.save!

        parent = FactoryBot.create(:team, parent: grandparent, name: "Parent")

        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: parent.id } }
        end.to change(Team, :count).by(1)

        team = Team.last
        expect(team.parent_id).to eq(parent.id)
      end

      it "prevents creating subteams for teams owned by other users" do
        other_user_team = FactoryBot.build(:team, :no_initial_admin, name: "Other User's Team")
        other_user_team.direct_memberships.build(user: other_user, role: "admin")
        other_user_team.save!

        expect do
          post developer_teams_path, params: { team: { name: "Child Team", parent_id: other_user_team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "respects the team depth limit" do
        team = parent_team
        (Team::TEAM_DEPTH_LIMIT - 1).times do
          team = FactoryBot.create(:team, parent: team)
        end

        expect do
          post developer_teams_path, params: { team: { name: "Too Deep", parent_id: team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "respects the subteam limit" do
        5.times { FactoryBot.create(:team, parent: parent_team) }

        expect do
          post developer_teams_path, params: { team: { name: "Sixth Child", parent_id: parent_team.id } }
        end.not_to change(Team, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when parent_id is provided via query parameter" do
      let!(:parent_team) do
        team = FactoryBot.build(:team, :no_initial_admin, name: "Parent Team")
        team.direct_memberships.build(user: user, role: "admin")
        team.save!
        team
      end

      it "pre-selects the parent in the new form" do
        get new_developer_team_path(parent_id: parent_team.id)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(parent_team.id)
        expect(response.body).to include(parent_team.name)
      end
    end
  end

  describe "GET /developer/teams/:id (show)" do
    let!(:team) do
      team = FactoryBot.build(:team, :no_initial_admin, name: "Show Team")
      team.direct_memberships.build(user: other_user, role: "admin")
      team.save!
      team
    end

    it "allows developers to view the team" do
      FactoryBot.create(:team_membership, :developer, team: team, user: user)

      get developer_team_path(team)

      expect(response).to have_http_status(:success)
    end

    it "allows managers to view the team" do
      FactoryBot.create(:team_membership, :manager, team: team, user: user)

      get developer_team_path(team)

      expect(response).to have_http_status(:success)
    end

    it "redirects members who lack show permission" do
      FactoryBot.create(:team_membership, team: team, user: user)

      get developer_team_path(team)

      expect(response).to redirect_to(developer_teams_path)
    end
  end

  describe "PATCH /developer/teams/:id (update)" do
    let!(:team) do
      team = FactoryBot.build(:team, :no_initial_admin, name: "Original Name")
      team.direct_memberships.build(user: user, role: "admin")
      team.save!
      team
    end

    it "allows updating the team name" do
      patch developer_team_path(team), params: { team: { name: "Updated Name" } }

      expect(response).to redirect_to(developer_team_path(team))
      expect(team.reload.name).to eq("Updated Name")
    end

    it "prevents updating parent_id even if provided" do
      other_team = FactoryBot.create(:team)

      patch developer_team_path(team), params: { team: { name: "Updated Name", parent_id: other_team.id } }

      expect(team.reload.parent_id).to be_nil
    end

    it "allows managers to update the team" do
      manager_team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :manager, team: manager_team, user: user)

      patch developer_team_path(manager_team), params: { team: { name: "Manager Updated" } }

      expect(response).to redirect_to(developer_team_path(manager_team))
      expect(manager_team.reload.name).to eq("Manager Updated")
    end

    it "prevents developers from updating the team" do
      dev_team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :developer, team: dev_team, user: user)

      expect do
        patch developer_team_path(dev_team), params: { team: { name: "Dev Updated" } }
      end.to raise_error(CanCan::AccessDenied)
    end

    it "prevents non-admins from updating the team" do
      sign_in other_user

      expect do
        patch developer_team_path(team), params: { team: { name: "Hacked Name" } }
      end.to raise_error(CanCan::AccessDenied)
    end

    it "prevents updating system teams (readonly)" do
      special_id = "00000000-0000-8000-8f0f-0000deadbeef"
      system_team = FactoryBot.create(:team, id: special_id, name: "System Team")
      FactoryBot.create(:team_membership, team: system_team, user: user, role: "admin")

      patch developer_team_path(system_team), params: { team: { name: "Hacked System" } }

      expect(response).to redirect_to(developer_team_path(system_team))
      expect(flash[:alert]).to be_present
      expect(system_team.reload.name).to eq("System Team")
    end
  end

  describe "DELETE /developer/teams/:id (destroy)" do
    let!(:team) do
      team = FactoryBot.build(:team, :no_initial_admin, name: "Test Team")
      team.direct_memberships.build(user: user, role: "admin")
      team.save!
      team
    end

    it "allows deleting a team with no children" do
      expect do
        delete developer_team_path(team)
      end.to change(Team, :count).by(-1)

      expect(response).to redirect_to(developer_teams_path)
    end

    it "prevents deleting a team with child teams" do
      child = FactoryBot.create(:team, parent: team)

      delete developer_team_path(team)

      expect(response).to redirect_to(developer_teams_path)
      expect(flash[:alert]).to match(/child teams/i)
      expect(Team.exists?(team.id)).to be true
      expect(Team.exists?(child.id)).to be true
    end

    it "prevents deleting system teams (readonly)" do
      special_id = "00000000-0000-8000-8f0f-0000deadbeef"
      system_team = FactoryBot.create(:team, id: special_id, name: "System Team")
      FactoryBot.create(:team_membership, team: system_team, user: user, role: "admin")

      delete developer_team_path(system_team)

      expect(flash[:alert]).to match(/system team/i)
      expect(Team.exists?(system_team.id)).to be true
    end

    it "prevents managers from deleting the team" do
      manager_team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :manager, team: manager_team, user: user)

      expect do
        delete developer_team_path(manager_team)
      end.to raise_error(CanCan::AccessDenied)
    end

    it "prevents non-admins from deleting the team" do
      sign_in other_user

      expect do
        delete developer_team_path(team)
      end.to raise_error(CanCan::AccessDenied)
    end

    it "prevents a direct admin from deleting their own subteam" do
      subteam = FactoryBot.create(:team, parent: team)
      FactoryBot.create(:team_membership, :admin, team: subteam, user: user)

      expect do
        delete developer_team_path(subteam)
      end.to raise_error(CanCan::AccessDenied)
    end

    it "allows a parent admin to delete a child subteam" do
      subteam = FactoryBot.create(:team, parent: team)

      expect do
        delete developer_team_path(subteam)
      end.to change(Team, :count).by(-1)
    end
  end
end
