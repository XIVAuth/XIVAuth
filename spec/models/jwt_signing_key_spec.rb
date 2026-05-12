require "rails_helper"

RSpec.describe JwtSigningKey do
  describe "lifecycle and flags" do
    it "computes expired? correctly" do
      key = FactoryBot.create(:jwt_signing_keys_hmac)
      expect(key).not_to be_expired

      key.update!(expires_at: 10.minutes.from_now)
      expect(key).not_to be_expired

      key.update!(expires_at: 1.minute.ago)
      expect(key).to be_expired
    end

    it "computes active? correctly from enabled and expired" do
      key = FactoryBot.create(:jwt_signing_keys_hmac)
      expect(key).to be_active

      key.update!(enabled: false)
      expect(key).not_to be_active

      key.update!(enabled: true, expires_at: 1.minute.ago)
      expect(key).not_to be_active
    end

    it "filters only active keys in .active scope" do
      active_rsa = FactoryBot.create(:jwt_signing_keys_rsa)
      inactive = FactoryBot.create(:jwt_signing_keys_hmac, enabled: false)
      expired = FactoryBot.create(:jwt_signing_keys_rsa, expires_at: 1.hour.ago)

      active_keys = described_class.active
      expect(active_keys).to include(active_rsa)
      expect(active_keys).not_to include(inactive)
      expect(active_keys).not_to include(expired)
    end

    it "returns name in to_param" do
      key = FactoryBot.create(:jwt_signing_keys_hmac)
      expect(key.to_param).to eq(key.name)
    end
  end

  describe "JWKS and JWK export" do
    it "includes only active keys in JWKS with correct kids" do
      rsa_active = FactoryBot.create(:jwt_signing_keys_rsa)
      hmac_active = FactoryBot.create(:jwt_signing_keys_hmac)
      expired = FactoryBot.create(:jwt_signing_keys_hmac, expires_at: 1.hour.ago)

      set = described_class.jwks
      expect(set).to be_a(JWT::JWK::Set)
      kids = set.export[:keys].pluck(:kid)

      expect(kids).to include(rsa_active.name, hmac_active.name)
      expect(kids).not_to include(expired.name)
    end

    it "exports algs and exp fields on JWK when present" do
      rsa = FactoryBot.create(:jwt_signing_keys_rsa, expires_at: 2.hours.from_now)

      jwk = rsa.jwk
      exported = jwk.export

      expect(exported[:kid]).to eq(rsa.name)
      expect(exported[:use]).to eq("sig")
      expect(exported[:algs]).to include(*rsa.supported_algorithms)
      expect(exported[:exp]).to be_within(5).of(rsa.expires_at.to_i)
    end
  end

  describe ".preferred_key_for_algorithm" do
    # Key generation is expensive, do it once and share across all tests
    before(:context) do
      @rsa_key = FactoryBot.create(:jwt_signing_keys_rsa)
      @hmac_key = FactoryBot.create(:jwt_signing_keys_hmac)
      @eddsa_key = FactoryBot.create(:jwt_signing_keys_ed25519)
      @ecdsa_key = FactoryBot.create(:jwt_signing_keys_ecdsa, curve: "prime256v1")
    end

    after(:context) do
      # Clean up keys to prevent test pollution
      @rsa_key&.destroy
      @hmac_key&.destroy
      @eddsa_key&.destroy
      @ecdsa_key&.destroy
    end

    it "returns RSA for RS256 and PS256 families" do
      expect(described_class.preferred_key_for_algorithm("RS256")).to eq(@rsa_key)
      expect(described_class.preferred_key_for_algorithm("PS256")).to eq(@rsa_key)
    end

    it "returns HMAC for HS256 family" do
      expect(described_class.preferred_key_for_algorithm("HS256")).to eq(@hmac_key)
    end

    it "returns Ed25519 for EdDSA" do
      expect(described_class.preferred_key_for_algorithm("EdDSA")).to eq(@eddsa_key)
    end

    it "returns a matching ECDSA key for ECDSA curves" do
      expect(described_class.preferred_key_for_algorithm("ES256")).to eq(@ecdsa_key)
    end

    it "returns nil for unknown algorithm" do
      expect(described_class.preferred_key_for_algorithm("foo.bar")).to be_nil
    end
  end

  it "raises NoMethodError for supported_algorithms in base class" do
    key = described_class.new(name: "base_test_#{SecureRandom.uuid}")
    expect { key.supported_algorithms }.to raise_error(NoMethodError, /Must be implemented by subclass/)
  end

  describe "encryption" do
    it "has encryption configured for private_key" do
      # Verify that the private_key attribute is marked as encrypted
      encrypted_attributes = described_class.encrypted_attributes
      expect(encrypted_attributes).to include(:private_key)
    end

    it "calls encryption when saving private_key" do
      encryptor = ActiveRecord::Encryption.encryptor
      expect(encryptor).to receive(:encrypt).at_least(:once).and_call_original

      FactoryBot.create(:jwt_signing_keys_hmac)
    end

    it "calls decryption when reading private_key" do
      key = FactoryBot.create(:jwt_signing_keys_hmac)

      encryptor = ActiveRecord::Encryption.encryptor
      expect(encryptor).to receive(:decrypt).at_least(:once).and_call_original

      # Reload to ensure we're reading from DB
      reloaded_key = described_class.find(key.id)
      reloaded_key.private_key
    end
  end
end
