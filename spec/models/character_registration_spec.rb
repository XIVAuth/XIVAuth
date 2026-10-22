require "rails_helper"

RSpec.describe CharacterRegistration do
  context "base validations" do
    before do
      @character = FactoryBot.create(:ffxiv_character)
      @user = FactoryBot.create(:user)

      @registration = described_class.create(user: @user, character: @character)
    end

    context "verification validations" do
      it "is valid if both verified_at and verification_type are set" do
        @registration.verified_at = Time.current
        @registration.verification_type = "test"

        expect(@registration).to be_valid
      end

      it "is invalid if verified_at is missing but verification_type is set" do
        @registration.verification_type = "test"

        expect(@registration).not_to be_valid
        expect(@registration.errors[:verification_type].first).to eq("must be blank")
      end

      it "is invalid if verified_at is set but verification_type is missing" do
        @registration.verified_at = Time.current

        expect(@registration).not_to be_valid
        expect(@registration.errors[:verification_type].first).to eq("can't be blank")
      end
    end
  end

  context "clobbering registrations" do
    before do
      @character = FactoryBot.create(:ffxiv_character)
      @existing_verified = described_class.create(
        user: FactoryBot.create(:user),
        character: @character,
        verified_at: Time.current,
        verification_type: "test"
      )
    end

    it "clobbers the old registration when asked" do
      new_registration = described_class.create(
        user: FactoryBot.create(:user),
        character: @character
      )

      new_registration.verify!("test", clobber: true)
      @existing_verified.reload  # mutated above, need to grab from DB again.

      expect(new_registration).to be_verified
      expect(@existing_verified).not_to be_verified
    end

    it "does not clobber the old registration if not asked" do
      new_registration = described_class.create(
        user: FactoryBot.create(:user),
        character: @character
      )

      expect do
        new_registration.verify!("test", clobber: false)
      end.to raise_error(ActiveRecord::RecordInvalid, "Validation failed: Character has already been verified.")

      @existing_verified.reload  # possibly mutated above, need to grab from DB again.

      expect(@existing_verified).to be_verified
      expect(new_registration).not_to be_verified
    end
  end

  context "derived secrets" do
    let(:registration) do
      described_class.new(user: FactoryBot.create(:user), character: FactoryBot.create(:ffxiv_character))
    end

    def stub_seeds(verification: nil, entanglement: nil)
      credentials = Rails.application.credentials
      allow(credentials).to receive(:dig).and_call_original
      allow(credentials).to receive(:dig).with(:xivauth, :character, :verification_seed).and_return(verification)
      allow(credentials).to receive(:dig).with(:xivauth, :character, :entanglement_seed).and_return(entanglement)
    end

    def legacy_seed(salt)
      Base64.strict_encode64(Rails.application.key_generator.generate_key(salt))
    end

    it "falls back to secret_key_base derivation when seeds are unset" do
      stub_seeds

      expect(described_class.seed_secret(:entanglement_seed, key_base_salt: "CharacterEntanglementSecret"))
        .to eq(Rails.application.key_generator.generate_key("CharacterEntanglementSecret"))
    end

    it "preserves existing values when seeds are set to the legacy derived keys" do
      stub_seeds
      legacy_verification_key = registration.verification_key
      legacy_entangled_id = registration.entangled_id

      stub_seeds(verification: legacy_seed("CharacterVerificationSecret"),
                 entanglement: legacy_seed("CharacterEntanglementSecret"))

      expect(registration.verification_key).to eq(legacy_verification_key)
      expect(registration.entangled_id).to eq(legacy_entangled_id)
    end

    it "uses the configured seeds when set" do
      verification_seed = SecureRandom.bytes(64)
      entanglement_seed = SecureRandom.bytes(64)
      stub_seeds(verification: Base64.strict_encode64(verification_seed),
                 entanglement: Base64.strict_encode64(entanglement_seed))

      input = "#{registration.character.lodestone_id}###{registration.user.id}"
      expected_entangled_id = Base64.urlsafe_encode64(
        OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha1"), entanglement_seed, input), padding: false
      )
      expected_verification_hmac = OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), verification_seed, input)
      expected_verification_code = Crockford.encode_string(expected_verification_hmac)
                                            .truncate(described_class::VERIFICATION_KEY_LENGTH, omission: "")

      expect(registration.entangled_id).to eq(expected_entangled_id)
      expect(registration.verification_key)
        .to eq("#{described_class::VERIFICATION_KEY_PREFIX}#{expected_verification_code}")
    end
  end
end
