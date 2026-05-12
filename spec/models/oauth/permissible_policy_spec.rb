require "rails_helper"

RSpec.describe OAuth::PermissiblePolicy do
  context "allow rule present" do
    before do
      @policy = described_class.create
      @resource = FactoryBot.create(:ffxiv_character)

      @policy.rules.create(resource: @resource, deny: false)
    end

    it "allows access to the specified resource" do
      expect(@policy.can_access_resource?(@resource)).to be true
    end

    it "blocks access to other resources (implicit deny)" do
      another_resource = FactoryBot.create(:ffxiv_character)
      expect(@policy.can_access_resource?(another_resource)).to be false
    end

    it "blocks access if an explicit deny is specified" do
      @policy.rules.create(resource: @resource, deny: true)
      expect(@policy.can_access_resource?(@resource)).to be false
    end
  end

  context "deny rule present" do
    before do
      @policy = described_class.create
      @resource = FactoryBot.create(:ffxiv_character)

      @policy.rules.create(resource: @resource, deny: true)
    end

    it "blocks access to the specified resource" do
      expect(@policy.can_access_resource?(@resource)).to be false
    end

    it "allows access to other resources (no implicit deny)" do
      another_resource = FactoryBot.create(:ffxiv_character)
      expect(@policy.can_access_resource?(another_resource)).to be true
    end

    it "blocks access even if an explicit allow is specified" do
      @policy.rules.create(resource: @resource, deny: false)
      expect(@policy.can_access_resource?(@resource)).to be false
    end
  end

  context "no rules present" do
    before do
      @policy = described_class.create
    end

    it "allows access to all resources" do
      resource = FactoryBot.create(:ffxiv_character)
      expect(@policy.can_access_resource?(resource)).to be true
    end

    it "respects the fallback parameter" do
      resource = FactoryBot.create(:ffxiv_character)
      expect(@policy.can_access_resource?(resource, fallback: true)).to be true
      expect(@policy.can_access_resource?(resource, fallback: false)).to be false
    end
  end

  context "mixed mode (multiple resource types in a single policy)" do
    before do
      @user_resource = FactoryBot.create(:user)
      @allowed_resource = FactoryBot.create(:ffxiv_character)
      @denied_resource = User::SocialIdentity.create(
        external_id: "abcdef", provider: "test",
        user: @user_resource
      )

      @policy = described_class.create
      @policy.rules.create(resource: @allowed_resource, deny: false)
      @policy.rules.create(resource: @denied_resource, deny: true)
    end

    it "uses implicit deny for a resource if an allow rule is present" do
      resource = FactoryBot.create(:ffxiv_character)

      expect(@policy.can_access_resource?(resource)).to be false
    end

    it "uses implicit allow for a resource if no allow rules are present" do
      resource = User::SocialIdentity.create(external_id: "wolf", provider: "test", user: @user_resource)

      expect(@policy.can_access_resource?(resource)).to be true
    end

    it "uses implicit allow if no rules are present for the resource type" do
      expect(@policy.can_access_resource?(@user_resource)).to be true
    end

    it "still evaluates explicit rules correctly" do
      expect(@policy.can_access_resource?(@allowed_resource)).to be true
      expect(@policy.can_access_resource?(@denied_resource)).to be false
    end
  end
end
