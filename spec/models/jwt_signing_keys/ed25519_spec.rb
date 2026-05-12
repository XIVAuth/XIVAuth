require "rails_helper"

RSpec.describe JwtSigningKeys::Ed25519 do
  subject { described_class.new(name: "rspec_ed25519_#{SecureRandom.uuid}") }

  context "crypto verification" do
    it "can sign and verify a message" do
      data = "This is a super secret message. #{SecureRandom.alphanumeric}"

      signature_bytes = subject.private_key.sign(data)
      expect(subject.public_key.verify(signature_bytes, data)).to be true
    end

    it "has a public key that matches the private key" do
      expect(subject.public_key.to_bytes).to eq(subject.private_key.verify_key.to_bytes)
    end

    it "reports supported algorithms" do
      expect(subject.supported_algorithms).to contain_exactly("Ed25519", "EdDSA")
    end
  end

  context "ActiveRecord shenanigans" do
    it "is not valid without a name" do
      subject.name = nil
      expect(subject).not_to be_valid
    end

    it "contains a valid keypair at initialization" do
      expect(subject.public_key).to be_an_instance_of(Ed25519::VerifyKey)
      expect(subject.private_key).to be_an_instance_of(Ed25519::SigningKey)
    end

    it "correctly persists the keypair" do
      subject.save

      ci = described_class.find_by(name: subject.name)
      expect(ci.raw_private_key).to eq(subject.raw_private_key)
      expect(ci.raw_public_key).to eq(subject.raw_public_key)
    end

    it "rejects mismatched public and private keys" do
      subject[:public_key] = OpenSSL::PKey.new_raw_public_key("Ed25519", "\x00" * 32).public_to_pem

      expect(subject).not_to be_valid
      expect(subject.errors[:public_key]).to include("must be consistent with the private key")
    end
  end
end
