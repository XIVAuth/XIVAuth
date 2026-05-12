require "rails_helper"

RSpec.describe CharacterRegistrationRequest do
  let(:user) { FactoryBot.create(:user) }

  def load_fixture(filename)
    file_path = Rails.root.join("spec/fixtures/lodestone/characters/#{filename}")
    JSON.parse(File.read(file_path))
  end

  def mock_lodestone_profile(lodestone_id, fixture_file)
    json_object = load_fixture(fixture_file)
    allow(FFXIV::LodestoneProfile).to receive(:new).with(lodestone_id, force_fresh: true).and_return(
      FFXIV::LodestoneProfile.new(lodestone_id, json_object: json_object)
    )
  end

  def mock_search_results(name:, world:, results: [], error: nil, error_status: nil)
    search_double = instance_double(
      FFXIV::LodestoneSearch,
      results: results,
      error: error,
      error_status: error_status,
      error?: error.present? || error_status.present?
    )
    allow(FFXIV::LodestoneSearch).to receive(:new)
      .with(name: name, world: world, exact: false)
      .and_return(search_double)
  end

  describe "validations" do
    it "validates lodestone_url format when present" do
      request = described_class.new(
        lodestone_url: "not-a-valid-id",
        user: user
      )

      expect(request).not_to be_valid
      expect(request.errors[:lodestone_url]).to be_present
    end

    it "allows valid lodestone URLs" do
      request = described_class.new(
        lodestone_url: "https://na.finalfantasyxiv.com/lodestone/character/12345678/",
        user: user
      )

      # NOTE: This only validates format, not that it processes successfully
      expect(request.errors[:lodestone_url]).to be_empty
    end

    it "allows bare lodestone IDs" do
      request = described_class.new(
        lodestone_url: "12345678",
        user: user
      )

      expect(request.errors[:lodestone_url]).to be_empty
    end
  end

  describe "#process! with Lodestone ID" do
    context "with valid character" do
      it "creates a character registration successfully" do
        mock_lodestone_profile("12345678", "valid_withcode.json")

        request = described_class.new(
          lodestone_url: "12345678",
          user: user
        )

        expect do
          result = request.process!
          expect(result).to eq(:success)
        end.to change(CharacterRegistration, :count).by(1)
                                                    .and change(FFXIV::Character, :count).by(1)

        registration = CharacterRegistration.last
        expect(registration.user).to eq(user)
        expect(registration.character.lodestone_id).to eq("12345678")
      end

      it "extracts and stores region from full URL" do
        mock_lodestone_profile("87654321", "valid_withcode.json")

        request = described_class.new(
          lodestone_url: "https://eu.finalfantasyxiv.com/lodestone/character/87654321/",
          user: user
        )

        result = request.process!

        expect(result).to eq(:success)
        registration = CharacterRegistration.last
        expect(registration.extra_data["region"]).to eq("eu")
        expect(registration.character.lodestone_id).to eq("87654321")
      end
    end

    context "with invalid character" do
      it "returns :invalid and adds error for not found character" do
        mock_lodestone_profile("99999999", "not_found.json")

        request = described_class.new(
          lodestone_url: "99999999",
          user: user
        )

        expect do
          result = request.process!
          expect(result).to eq(:invalid)
          expect(request.errors[:lodestone_url]).to be_present
        end.not_to(change(CharacterRegistration, :count))
      end

      it "returns :failed and adds error for hidden character" do
        mock_lodestone_profile("88888888", "hidden.json")

        request = described_class.new(
          lodestone_url: "88888888",
          user: user
        )

        expect do
          result = request.process!
          expect(result).to eq(:failed)
          # Hidden character is a character-origin error, not a user input error
          expect(request.errors[:character]).to be_present
          expect(request.errors[:character].first).to include("hidden")
          expect(request.errors[:lodestone_url]).to be_empty
        end.not_to change(CharacterRegistration, :count)
      end

      it "does not add duplicate errors" do
        mock_lodestone_profile("99999999", "not_found.json")

        request = described_class.new(
          lodestone_url: "99999999",
          user: user
        )

        request.process!

        # Should only have one error on the field, not field + base errors
        lodestone_errors = request.errors[:lodestone_url]
        base_errors = request.errors[:base]

        expect(lodestone_errors.count).to eq(1)
        expect(base_errors.count).to eq(0)
      end
    end

    context "with service errors" do
      it "returns :failed and adds error to :character when Lodestone is under maintenance" do
        mock_lodestone_profile("77777777", "maintenance.json")

        request = described_class.new(
          lodestone_url: "77777777",
          user: user
        )

        result = request.process!

        expect(result).to eq(:failed)
        # Service errors are character-origin errors, not user input errors
        expect(request.errors[:character]).to be_present
        expect(request.errors[:character].first).to include("maintenance")
        expect(request.errors[:lodestone_url]).to be_empty
      end
    end

    context "with malformed input" do
      it "returns :invalid with error for invalid lodestone ID format" do
        request = described_class.new(
          lodestone_url: "invalid",
          user: user
        )

        result = request.process!

        expect(result).to eq(:invalid)
        expect(request.errors[:lodestone_url]).to be_present
      end
    end
  end

  describe "#process! with search (name + world)" do
    context "with single search result" do
      it "creates a character registration automatically" do
        mock_lodestone_profile("56781234", "valid_withcode.json")
        mock_search_results(
          name: "Abe Eon",
          world: "Gilgamesh",
          results: [
            { lodestone_id: 56_781_234, name: "Abe Eon", world: "Gilgamesh", datacenter: "Aether", avatar_url: "https://example.com/avatar.jpg" }
          ]
        )

        request = described_class.new(
          search_name: "Abe Eon",
          search_world: "Gilgamesh",
          user: user
        )

        expect do
          result = request.process!
          expect(result).to eq(:success)
        end.to change(CharacterRegistration, :count).by(1)

        registration = CharacterRegistration.last
        expect(registration.character.lodestone_id).to eq("56781234")
      end
    end

    context "with multiple search results" do
      it "returns :confirm and populates candidates" do
        mock_search_results(
          name: "John Doe",
          world: "Gilgamesh",
          results: [
            { lodestone_id: 11_111_111, name: "John Doe", world: "Gilgamesh", datacenter: "Aether",
              avatar_url: "https://example.com/1.jpg" },
            { lodestone_id: 22_222_222, name: "John Doe", world: "Gilgamesh", datacenter: "Aether", avatar_url: "https://example.com/2.jpg" }
          ]
        )

        request = described_class.new(
          search_name: "John Doe",
          search_world: "Gilgamesh",
          user: user
        )

        # No registration created yet
        expect do
          result = request.process!
          expect(result).to eq(:confirm)
          expect(request.candidates.count).to eq(2)
          expect(request.candidates.first[:lodestone_id]).to eq(11_111_111)
        end.not_to change(CharacterRegistration, :count)
      end
    end

    context "with no search results" do
      it "returns :invalid with error message" do
        mock_search_results(
          name: "Nonexistent Character",
          world: "Gilgamesh",
          results: []
        )

        request = described_class.new(
          search_name: "Nonexistent Character",
          search_world: "Gilgamesh",
          user: user
        )

        result = request.process!

        expect(result).to eq(:invalid)
        expect(request.errors[:character_search]).to be_present
        expect(request.errors[:character_search].first).to include("could not find")
      end
    end

    context "with too many search results" do
      it "returns :invalid with refine search message" do
        # Generate 11 results to exceed the limit of 10
        results = (1..11).map do |i|
          { lodestone_id: i, name: "Common Name", world: "Gilgamesh", datacenter: "Aether", avatar_url: "https://example.com/#{i}.jpg" }
        end

        mock_search_results(
          name: "Common Name",
          world: "Gilgamesh",
          results: results
        )

        request = described_class.new(
          search_name: "Common Name",
          search_world: "Gilgamesh",
          user: user
        )

        result = request.process!

        expect(result).to eq(:invalid)
        expect(request.errors[:character_search]).to be_present
        expect(request.errors[:character_search].first).to include("too many characters")
      end
    end

    context "with search API errors" do
      it "returns :failed when search service has error" do
        mock_search_results(
          name: "Any Name",
          world: "Gilgamesh",
          results: [],
          error: "Rate limited. Please try again in a moment."
        )

        request = described_class.new(
          search_name: "Any Name",
          search_world: "Gilgamesh",
          user: user
        )

        result = request.process!

        expect(result).to eq(:failed)
        expect(request.errors[:character_search]).to be_present
      end
    end
  end

  describe "#process! with missing inputs" do
    it "returns :invalid when no inputs provided" do
      request = described_class.new(user: user)

      result = request.process!

      expect(result).to eq(:invalid)
      expect(request.errors[:base]).to be_present
      expect(request.errors[:base].first).to include("provide either")
    end

    it "returns :invalid when only search name provided" do
      request = described_class.new(
        search_name: "Abe Eon",
        user: user
      )

      result = request.process!

      expect(result).to eq(:invalid)
      expect(request.errors[:base]).to be_present
    end

    it "returns :invalid when only search world provided" do
      request = described_class.new(
        search_world: "Gilgamesh",
        user: user
      )

      result = request.process!

      expect(result).to eq(:invalid)
      expect(request.errors[:base]).to be_present
    end
  end

  describe "error mapping" do
    it "maps character errors to the specified field" do
      mock_lodestone_profile("99999999", "not_found.json")

      request = described_class.new(
        lodestone_url: "99999999",
        user: user
      )

      request.process!

      # Character validation errors should be on lodestone_url field
      expect(request.errors[:lodestone_url]).to be_present
      # Not on base
      expect(request.errors[:base]).to be_empty
    end

    it "maps hidden character errors to :character regardless of input method" do
      mock_lodestone_profile("88888888", "hidden.json")
      mock_search_results(
        name: "Hidden Character",
        world: "Gilgamesh",
        results: [
          { lodestone_id: 88_888_888, name: "Hidden Character", world: "Gilgamesh", datacenter: "Aether", avatar_url: "https://example.com/avatar.jpg" }
        ]
      )

      request = described_class.new(
        search_name: "Hidden Character",
        search_world: "Gilgamesh",
        user: user
      )

      request.process!

      # Hidden character errors are character-origin, not user input errors
      expect(request.errors[:character]).to be_present
      expect(request.errors[:character].first).to include("hidden")
      expect(request.errors[:search_name]).to be_empty
    end
  end
end
