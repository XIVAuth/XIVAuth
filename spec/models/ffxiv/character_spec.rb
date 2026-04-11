require "rails_helper"

RSpec.describe FFXIV::Character, type: :model do
  let(:fixtures_path) { Rails.root.join("spec/fixtures/lodestone/characters") }

  def load_fixture(filename)
    JSON.parse(File.read(fixtures_path.join(filename)))
  end

  def mock_lodestone_profile(lodestone_id, fixture_file)
    json_object = load_fixture(fixture_file)
    allow(FFXIV::LodestoneProfile).to receive(:new).with(lodestone_id).and_return(
      FFXIV::LodestoneProfile.new(lodestone_id, json_object: json_object)
    )
  end

  describe "#refresh_from_lodestone" do
    context "when a refresh succeeds" do
      it "updates character attributes from Lodestone" do
        character = FactoryBot.create(:ffxiv_character, lodestone_id: "12345678")
        mock_lodestone_profile("12345678", "valid_withcode.json")

        character.refresh_from_lodestone

        expect(character.name).to eq("Abe Eon")
        expect(character.home_world).to eq("Lamia")
        expect(character.data_center).to eq("Primal")
        expect(character.refresh_fail_reason).to be_nil
      end

      it "clears previous refresh_fail_reason on successful refresh" do
        character = FactoryBot.create(:ffxiv_character,
                                      lodestone_id: "12345678",
                                      refresh_fail_reason: :lodestone_maintenance)
        mock_lodestone_profile("12345678", "valid_withcode.json")

        character.refresh_from_lodestone

        expect(character.refresh_fail_reason).to be_nil
      end
    end

    context "when a refresh fails" do
      it "sets refresh_fail_reason for not_found character" do
        character = FactoryBot.create(:ffxiv_character,
                                      lodestone_id: "99999999",
                                      name: "Existing Name")
        mock_lodestone_profile("99999999", "not_found.json")

        character.refresh_from_lodestone

        expect(character.refresh_fail_reason).to eq(:not_found)
        # Existing data should remain unchanged when refresh fails
        expect(character.name).to eq("Existing Name")
      end

      it "sets refresh_fail_reason for hidden character" do
        character = FactoryBot.create(:ffxiv_character,
                                      lodestone_id: "88888888",
                                      name: "Existing Name")
        mock_lodestone_profile("88888888", "hidden.json")

        character.refresh_from_lodestone

        expect(character.refresh_fail_reason).to eq(:hidden_character)
        # Existing data should remain unchanged when refresh fails
        expect(character.name).to eq("Existing Name")
      end

      it "sets refresh_fail_reason for Lodestone maintenance" do
        character = FactoryBot.create(:ffxiv_character,
                                      lodestone_id: "77777777",
                                      name: "Existing Name")
        mock_lodestone_profile("77777777", "maintenance.json")

        character.refresh_from_lodestone

        expect(character.refresh_fail_reason).to eq(:lodestone_maintenance)
        # Character data should not be updated during maintenance
        expect(character.name).to eq("Existing Name")
      end

      it "does not overwrite existing character data on a failure" do
        character = FactoryBot.create(:ffxiv_character,
                                      lodestone_id: "77777777",
                                      name: "Existing Name",
                                      home_world: "Existing World",
                                      data_center: "Existing DC")
        mock_lodestone_profile("77777777", "maintenance.json")

        character.refresh_from_lodestone

        # Existing data should remain unchanged
        expect(character.name).to eq("Existing Name")
        expect(character.home_world).to eq("Existing World")
        expect(character.data_center).to eq("Existing DC")
        expect(character.refresh_fail_reason).to eq(:lodestone_maintenance)
      end
    end

    context "with private profile" do
      it "sets refresh_fail_reason but still updates data" do
        character = FactoryBot.create(:ffxiv_character, lodestone_id: "12345678")
        mock_lodestone_profile("12345678", "profile_private.json")

        character.refresh_from_lodestone

        expect(character.refresh_fail_reason).to eq(:profile_private)
        # Note: private profiles are still "valid" and provide basic data
        expect(character.name).to eq("Private Character")
        expect(character.home_world).to eq("Twintania")
        expect(character.data_center).to eq("Light")
      end
    end
  end

  describe ".for_lodestone_id" do
    context "when character does not exist in database" do
      it "returns an unsaved character populated from Lodestone" do
        mock_lodestone_profile("12345678", "valid_withcode.json")

        character = FFXIV::Character.for_lodestone_id("12345678")

        expect(character).to be_new_record
        expect(character).to be_valid
        expect(character.name).to eq("Abe Eon")
        expect(character.lodestone_id).to eq("12345678")
      end
    end

    context "when character already exists in database" do
      it "returns the existing character without creating a new one" do
        existing = FactoryBot.create(:ffxiv_character, lodestone_id: "12345678")

        character = FFXIV::Character.for_lodestone_id("12345678")

        expect(character.id).to eq(existing.id)
        expect(character).to be_persisted
      end
    end

    context "when a lodestone request fails" do
      it "does not save character with not_found error" do
        mock_lodestone_profile("99999999", "not_found.json")

        character = FFXIV::Character.for_lodestone_id("99999999")
        expect(character).not_to be_persisted
        expect(character).to be_invalid
        expect(character.refresh_fail_reason).to eq(:not_found)
      end

      it "does not save character with hidden error" do
        mock_lodestone_profile("88888888", "hidden.json")

        character = FFXIV::Character.for_lodestone_id("88888888")
        expect(character).not_to be_persisted
        expect(character).to be_invalid
        expect(character.refresh_fail_reason).to eq(:hidden_character)
      end

      it "does not save character with maintenance error" do
        mock_lodestone_profile("77777777", "maintenance.json")

        character = FFXIV::Character.for_lodestone_id("77777777")
        expect(character).not_to be_persisted
        expect(character).to be_invalid
        expect(character.refresh_fail_reason).to eq(:lodestone_maintenance)
      end
    end
  end

  describe "#implicit_order_column" do
    it "uses lodestone_id as its implicit order" do
      expect(subject.class.implicit_order_column).to eq("lodestone_id")
    end
  end
end
