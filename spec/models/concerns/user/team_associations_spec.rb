require "rails_helper"

RSpec.describe User::TeamAssociations do
  let(:user) { FactoryBot.create(:user) }

  describe "#teams_by_membership_scope" do
    context "with admin scope" do
      it "returns teams where user is directly an admin" do
        team = FactoryBot.build(:team, :no_initial_admin, name: "Admin Team")
        team.direct_memberships.build(user: user, role: "admin")
        team.save!

        expect(user.teams_by_membership_scope(:admins)).to contain_exactly(team)
      end

      it "includes all descendants regardless of inherit_parent_memberships flag" do
        parent = FactoryBot.build(:team, :no_initial_admin, name: "Parent")
        parent.direct_memberships.build(user: user, role: "admin")
        parent.save!

        # Child with inherit = false should still be included for admins
        child_no_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: false)
        child_with_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: true)

        expect(user.teams_by_membership_scope(:admins)).to contain_exactly(parent, child_no_inherit, child_with_inherit)
      end

      it "includes deeply nested descendants" do
        grandparent = FactoryBot.build(:team, :no_initial_admin, name: "Grandparent")
        grandparent.direct_memberships.build(user: user, role: "admin")
        grandparent.save!

        parent = FactoryBot.create(:team, parent: grandparent, inherit_parent_memberships: false)
        child = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: false)

        # Admin ignores all inherit flags
        expect(user.teams_by_membership_scope(:admins)).to contain_exactly(grandparent, parent, child)
      end
    end

    context "with developers scope" do
      it "returns teams where user is a developer or admin" do
        admin_team = FactoryBot.build(:team, :no_initial_admin, name: "Admin Team")
        admin_team.direct_memberships.build(user: user, role: "admin")
        admin_team.save!

        dev_team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :developer, team: dev_team, user: user)

        expect(user.teams_by_membership_scope(:developers)).to contain_exactly(admin_team, dev_team)
      end

      it "only includes descendants with inherit_parent_memberships = true" do
        parent = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :developer, team: parent, user: user)

        child_with_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: true)
        child_no_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: false)

        # Developer respects inherit flag
        expect(user.teams_by_membership_scope(:developers)).to contain_exactly(parent, child_with_inherit)
        expect(user.teams_by_membership_scope(:developers)).not_to include(child_no_inherit)
      end

      it "stops traversing when inherit_parent_memberships is false" do
        parent = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :developer, team: parent, user: user)

        child_no_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: false)
        grandchild = FactoryBot.create(:team, parent: child_no_inherit, inherit_parent_memberships: true)

        # Should not reach grandchild because child has inherit = false
        expect(user.teams_by_membership_scope(:developers)).to contain_exactly(parent)
        expect(user.teams_by_membership_scope(:developers)).not_to include(child_no_inherit, grandchild)
      end
    end

    context "with active scope" do
      it "returns teams where user has any active membership" do
        admin_team = FactoryBot.build(:team, :no_initial_admin, name: "Admin Team")
        admin_team.direct_memberships.build(user: user, role: "admin")
        admin_team.save!

        dev_team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :developer, team: dev_team, user: user)

        member_team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, team: member_team, user: user, role: "member")

        expect(user.teams_by_membership_scope(:active)).to contain_exactly(admin_team, dev_team, member_team)
      end

      it "respects inherit_parent_memberships flag" do
        parent = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, team: parent, user: user, role: "member")

        child_with_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: true)
        child_no_inherit = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: false)

        expect(user.teams_by_membership_scope(:active)).to contain_exactly(parent, child_with_inherit)
        expect(user.teams_by_membership_scope(:active)).not_to include(child_no_inherit)
      end

      it "excludes blocked and invited memberships" do
        team = FactoryBot.create(:team)
        FactoryBot.create(:team_membership, :blocked, team: team, user: user)

        expect(user.teams_by_membership_scope(:active)).to be_empty
      end
    end
  end

  describe "#associated_teams" do
    it "returns all teams user has access to via any membership" do
      admin_team = FactoryBot.build(:team, :no_initial_admin, name: "Admin Team")
      admin_team.direct_memberships.build(user: user, role: "admin")
      admin_team.save!

      dev_team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :developer, team: dev_team, user: user)

      member_team = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, team: member_team, user: user, role: "member")

      expect(user.associated_teams).to contain_exactly(admin_team, dev_team, member_team)
    end

    it "combines admin teams (ignoring inherit) with developer teams (respecting inherit)" do
      # Admin team with child that doesn't inherit
      admin_parent = FactoryBot.build(:team, :no_initial_admin, name: "Admin Parent")
      admin_parent.direct_memberships.build(user: user, role: "admin")
      admin_parent.save!
      admin_child_no_inherit = FactoryBot.create(:team, parent: admin_parent, inherit_parent_memberships: false)

      # Developer team with child that doesn't inherit
      dev_parent = FactoryBot.create(:team)
      FactoryBot.create(:team_membership, :developer, team: dev_parent, user: user)
      dev_child_no_inherit = FactoryBot.create(:team, parent: dev_parent, inherit_parent_memberships: false)

      # Admin child is included, dev child is not
      expect(user.associated_teams).to include(admin_parent, admin_child_no_inherit, dev_parent)
      expect(user.associated_teams).not_to include(dev_child_no_inherit)
    end

    it "does not double-count teams where user has multiple memberships" do
      team = FactoryBot.build(:team, :no_initial_admin, name: "Team")
      team.direct_memberships.build(user: user, role: "admin")
      team.save!

      # User is already admin, adding another membership shouldn't duplicate
      result = user.associated_teams
      expect(result.where(id: team.id).count).to eq(1)
    end

    it "handles complex inheritance scenarios" do
      # Grandparent where user is admin
      grandparent = FactoryBot.build(:team, :no_initial_admin, name: "Grandparent")
      grandparent.direct_memberships.build(user: user, role: "admin")
      grandparent.save!

      # Parent with inherit = false (but admin ignores this)
      parent = FactoryBot.create(:team, parent: grandparent, inherit_parent_memberships: false)

      # Child with inherit = true
      child = FactoryBot.create(:team, parent: parent, inherit_parent_memberships: true)

      # All should be included because user is admin at grandparent level
      expect(user.associated_teams).to contain_exactly(grandparent, parent, child)
    end

    it "returns unique teams when admin and developer overlap" do
      # Team where user is both admin directly
      team = FactoryBot.build(:team, :no_initial_admin, name: "Team")
      team.direct_memberships.build(user: user, role: "admin")
      team.save!

      # Child team
      child = FactoryBot.create(:team, parent: team, inherit_parent_memberships: true)

      result = user.associated_teams
      # Should only have 2 teams, not duplicates
      expect(result).to contain_exactly(team, child)
    end
  end
end
