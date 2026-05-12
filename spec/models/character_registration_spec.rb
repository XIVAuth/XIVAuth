require "rails_helper"

RSpec.describe CharacterRegistration, type: :model do
  context "base validations" do
    before do
      @character = FactoryBot.create(:ffxiv_character)
      @user = FactoryBot.create(:user)

      @registration = CharacterRegistration.create(user: @user, character: @character)
    end

    context "verification validations" do
      it "is valid if both verified_at and verification_type are set" do
        @registration.verified_at = Time.current
        @registration.verification_type = "test"

        expect(@registration).to be_valid
      end

      it "is invalid if verified_at is missing but verification_type is set" do
        @registration.verification_type = "test"

        expect(@registration).to be_invalid
        expect(@registration.errors[:verification_type].first).to eq("must be blank")
      end

      it "is invalid if verified_at is set but verification_type is missing" do
        @registration.verified_at = Time.current

        expect(@registration).to be_invalid
        expect(@registration.errors[:verification_type].first).to eq("can't be blank")
      end
    end
  end

  context "clobbering registrations" do
    before do
      @character = FactoryBot.create(:ffxiv_character)
      @existing_verified = CharacterRegistration.create(
        user: FactoryBot.create(:user),
        character: @character,
        verified_at: Time.current,
        verification_type: "test"
      )
    end

    it "clobbers the old registration when asked" do
      new_registration = CharacterRegistration.create(
        user: FactoryBot.create(:user),
        character: @character
      )

      new_registration.verify!("test", clobber: true)
      @existing_verified.reload  # mutated above, need to grab from DB again.

      expect(new_registration.verified?).to be_truthy
      expect(@existing_verified.verified?).to be_falsey
    end

    it "does not clobber the old registration if not asked" do
      new_registration = CharacterRegistration.create(
        user: FactoryBot.create(:user),
        character: @character
      )

      expect do
        new_registration.verify!("test", clobber: false)
      end.to raise_error(ActiveRecord::RecordInvalid, "Validation failed: Character has already been verified.")

      @existing_verified.reload  # possibly mutated above, need to grab from DB again.

      expect(@existing_verified.verified?).to be_truthy
      expect(new_registration.verified?).to be_falsey
    end
  end
end
