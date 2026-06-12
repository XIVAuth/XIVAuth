require "rails_helper"

RSpec.describe User do
  context "with an empty password" do
    before do
      @user = FactoryBot.build(:user, password: nil, encrypted_password: nil)
    end

    it "properly reports an empty password" do
      # Sanity test to ensure FactoryBot isn't going to cause problems for us.
      expect(@user.encrypted_password).to be_nil
      expect(@user.password_set?).to be(false)
      expect(@user.password).to be_nil
    end

    it "cleanly fails validation of any input password" do
      expect(@user.valid_password?("")).to be(false)
      expect(@user.valid_password?(nil)).to be(false)
      expect(@user.valid_password?("P@ssw0rd!")).to be(false)
    end

    it "fails initial validation without a social identity" do
      expect(@user).not_to be_valid
      expect(@user.errors[:password].first).to eq "can't be blank"
    end

    it "passes initial validation with a social identity" do
      @user.social_identities.build({ provider: "dummy", external_id: Random.uuid })

      expect(@user).to be_valid
    end
  end

  describe "#implicit_order_column" do
    it "uses created_at as its implicit order" do
      expect(subject.class.implicit_order_column).to eq("created_at")
    end
  end

  describe "#preferences" do
    let(:user) { FactoryBot.create(:user) }

    it "is empty on a new user" do
      expect(user.preferences_before_type_cast).to eq("{}")
    end

    it "sets default theme to auto" do
      expect(user.preferences.theme).to eq("auto")
    end

    it "correctly persists a theme change" do
      user.preferences.theme = "astral"
      user.save

      expect(user.reload.preferences.theme).to eq("astral")
    end
  end
end
