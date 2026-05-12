require "rails_helper"
require "cancan/matchers"

RSpec.describe Abilities::UserAbility do
  subject(:ability) { described_class.new(user) }

  let(:user) { FactoryBot.create(:user) }

  describe "Team permissions" do
    let(:team) { FactoryBot.create(:team) }

    # Helper: give the user a direct membership on the team with the given role
    def create_membership_with_role(role)
      FactoryBot.create(:team_membership, team: team, user: user, role: role)
    end

    shared_examples "cannot access team at all" do
      it { is_expected.not_to be_able_to(:use, team) }
      it { is_expected.not_to be_able_to(:show, team) }
      it { is_expected.not_to be_able_to(:create_apps, team) }
      it { is_expected.not_to be_able_to(:update, team) }
      it { is_expected.not_to be_able_to(:manage_users, team) }
      it { is_expected.not_to be_able_to(:destroy, team) }
    end

    context "with no membership" do
      it_behaves_like "cannot access team at all"
    end

    context "with blocked role" do
      before { create_membership_with_role("blocked") }

      it_behaves_like "cannot access team at all"
    end

    context "with invited role" do
      before { create_membership_with_role("invited") }

      it_behaves_like "cannot access team at all"
    end

    context "with member role" do
      before { create_membership_with_role("member") }

      it { is_expected.to be_able_to(:use, team) }
      it { is_expected.not_to be_able_to(:show, team) }
      it { is_expected.not_to be_able_to(:create_apps, team) }
      it { is_expected.not_to be_able_to(:update, team) }
      it { is_expected.not_to be_able_to(:manage_users, team) }
      it { is_expected.not_to be_able_to(:destroy, team) }
    end

    context "with developer role" do
      before { create_membership_with_role("developer") }

      it { is_expected.to be_able_to(:use, team) }
      it { is_expected.to be_able_to(:show, team) }
      it { is_expected.to be_able_to(:create_apps, team) }
      it { is_expected.not_to be_able_to(:update, team) }
      it { is_expected.not_to be_able_to(:manage_users, team) }
      it { is_expected.not_to be_able_to(:destroy, team) }
    end

    context "with manager role" do
      before { create_membership_with_role("manager") }

      it { is_expected.to be_able_to(:use, team) }
      it { is_expected.to be_able_to(:show, team) }
      it { is_expected.to be_able_to(:create_apps, team) }
      it { is_expected.to be_able_to(:update, team) }
      it { is_expected.to be_able_to(:manage_users, team) }
      it { is_expected.not_to be_able_to(:destroy, team) }
    end

    context "with admin role" do
      before { create_membership_with_role("admin") }

      it { is_expected.to be_able_to(:use, team) }
      it { is_expected.to be_able_to(:show, team) }
      it { is_expected.to be_able_to(:create_apps, team) }
      it { is_expected.to be_able_to(:update, team) }
      it { is_expected.to be_able_to(:manage_users, team) }
      it { is_expected.to be_able_to(:destroy, team) }
    end

    describe "admin destroy exception for subteams" do
      let(:parent) { FactoryBot.create(:team) }
      let(:subteam) { FactoryBot.create(:team, parent: parent) }

      it "blocks a direct admin from destroying their own subteam" do
        FactoryBot.create(:team_membership, :admin, team: subteam, user: user)

        expect(ability).not_to be_able_to(:destroy, subteam)
      end

      it "allows a parent admin to destroy a child subteam" do
        FactoryBot.create(:team_membership, :admin, team: parent, user: user)

        expect(ability).to be_able_to(:destroy, subteam)
      end

      it "allows a root admin to destroy a grandchild subteam" do
        grandchild = FactoryBot.create(:team, parent: subteam)
        FactoryBot.create(:team_membership, :admin, team: parent, user: user)

        expect(ability).to be_able_to(:destroy, grandchild)
      end

      it "allows an admin to destroy a root team" do
        FactoryBot.create(:team_membership, :admin, team: team, user: user)

        expect(ability).to be_able_to(:destroy, team)
      end
    end

    describe "create_subteam" do
      it "is denied for managers" do
        create_membership_with_role("manager")

        expect(ability).not_to be_able_to(:create_subteam, team)
      end

      it "is denied for developers" do
        create_membership_with_role("developer")

        expect(ability).not_to be_able_to(:create_subteam, team)
      end

      it "is allowed for admins via manage wildcard" do
        create_membership_with_role("admin")

        expect(ability).to be_able_to(:create_subteam, team)
      end
    end
  end

  describe "ClientApplication permissions (team-owned)" do
    let(:team) { FactoryBot.create(:team) }
    let(:app) { FactoryBot.create(:client_application, owner: team) }

    it "allows developers to manage team-owned apps" do
      FactoryBot.create(:team_membership, :developer, team: team, user: user)

      expect(ability).to be_able_to(:manage, app)
    end

    it "allows managers to manage team-owned apps" do
      FactoryBot.create(:team_membership, :manager, team: team, user: user)

      expect(ability).to be_able_to(:manage, app)
    end

    it "does not allow members to manage team-owned apps" do
      FactoryBot.create(:team_membership, team: team, user: user)

      expect(ability).not_to be_able_to(:manage, app)
    end
  end
end
