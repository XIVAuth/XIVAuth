require "rails_helper"

RSpec.describe FFXIV::LodestoneProfile, type: :model do
  let(:fixtures_path) { Rails.root.join("spec/fixtures/lodestone/characters") }

  def load_fixture(name)
    json_str = File.read(fixtures_path.join(name))

    JSON.parse(json_str)
  end

  describe ".new with injected Flarestone response" do
    it "parses a visible character with a verification code" do
      flarestone_response = load_fixture("valid_withcode.json")
      profile = described_class.new(43_809_410, json_object: flarestone_response)

      expect(profile).to be_valid
      expect(profile.failure_reason).to be_nil

      # Exact identity fields
      expect(profile.name).to eq("Abe Eon")
      expect(profile.title).to eq("King Bean")
      expect(profile.world).to eq("Lamia")
      expect(profile.datacenter).to eq("Primal")

      expect(profile.avatar).to match(%r{https://img2\.finalfantasyxiv\.com/f/[0-9a-f_]+fc0\.jpg})
      expect(profile.portrait).to match(%r{https://img2\.finalfantasyxiv\.com/f/[0-9a-f_]+fl0\.jpg})

      # Bio should include the code block from the fixture
      expect(profile.bio).to include("XIVAUTH:")

      # Class levels should include some jobs with integer values
      expect(profile.class_levels).to be_a(Hash)
      expect(profile.class_levels).not_to be_empty
      expect(profile.class_levels.values).to all(be_a(Hash).and(include(:level, :name)))

      # Free company info present in the fixture
      expect(profile.free_company).to include(:name, :id)
      expect(profile.free_company[:name]).to eq("Friendly Fire")
      expect(profile.free_company[:id]).to eq(9_231_112_598_714_485_863)

      # Misc
      expect(profile.paid_character?).to be(true)
    end

    it "detects a private profile page" do
      flarestone_response = load_fixture("profile_private.json")
      profile = described_class.new(12_345_678, json_object: flarestone_response)

      expect(profile).to be_valid
      expect(profile.failure_reason).to eq(:profile_private)

      expect(profile.name).to eq("Private Character")
      expect(profile.world).to eq("Twintania")
      expect(profile.datacenter).to eq("Light")

      expect(profile.avatar).to match(%r{https://img2\.finalfantasyxiv\.com/f/[0-9a-f_]+fc0\.jpg})
      expect(profile.portrait).to match(%r{https://img2\.finalfantasyxiv\.com/f/[0-9a-f_]+fl0\.jpg})
    end

    it "detects a hidden character page" do
      flarestone_response = load_fixture("hidden.json")
      profile = described_class.new(12_345_678, json_object: flarestone_response)

      expect(profile).to be_invalid
      expect(profile.failure_reason).to eq(:hidden_character)
      expect(profile.errors[:base].join).to match(/is marked as hidden or private/i)
    end

    it "detects a 404 not found page" do
      flarestone_response = load_fixture("not_found.json")
      profile = described_class.new(12_345_678, json_object: flarestone_response)

      expect(profile).to be_invalid
      expect(profile.failure_reason).to eq(:not_found)
      expect(profile.errors[:base].join).to match(/could not be found/i)
    end

    it "detects Lodestone maintenance" do
      flarestone_response = load_fixture("maintenance.json")
      profile = described_class.new(12_345_678, json_object: flarestone_response)

      expect(profile).to be_invalid
      expect(profile.failure_reason).to eq(:lodestone_maintenance)
      expect(profile.errors[:base].join).to match(/maintenance/i)
      expect(profile.errors.where(:base).first.type).to eq(:maintenance)
    end
  end
end
