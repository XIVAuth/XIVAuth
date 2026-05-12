require "rails_helper"

RSpec.describe PKI::IssuedCertificate do
  include ActiveSupport::Testing::TimeHelpers

  describe "validations" do
    it "requires certificate_pem" do
      cert = FactoryBot.build(:pki_issued_certificate, certificate_pem: nil)
      expect(cert).not_to be_valid
      expect(cert.errors[:certificate_pem]).to be_present
    end

    it "derives issued_at, expires_at, and fingerprints from certificate_pem" do
      cert = FactoryBot.build(:pki_issued_certificate)
      expect(cert.issued_at).to be_present
      expect(cert.expires_at).to be_present
      expect(cert.certificate_fingerprint).to be_present
      expect(cert.public_key_fingerprint).to be_present
    end

    it "derives public_key_info from the certificate" do
      cert = FactoryBot.build(:pki_issued_certificate)
      expect(cert.public_key_info).to be_present
      expect(cert.public_key_info["type"]).to be_present
      expect(cert.public_key_info["bits"]).to be_present
    end
  end

  describe ".find_by_serial" do
    it "round-trips UUID → integer → UUID correctly" do
      cert = FactoryBot.create(:pki_issued_certificate)
      serial_int = cert.id.delete("-").to_i(16)

      expect(described_class.lookup_by_serial(serial_int)).to eq(cert)
    end

    it "accepts OpenSSL::BN as input" do
      cert = FactoryBot.create(:pki_issued_certificate)
      serial_bn = OpenSSL::BN.new(cert.id.delete("-"), 16)

      expect(described_class.lookup_by_serial(serial_bn.to_i)).to eq(cert)
    end

    it "returns nil for unknown serials" do
      expect(described_class.lookup_by_serial(0)).to be_nil
    end
  end

  describe "#revoke!" do
    it "sets revoked_at and revocation_reason" do
      cert = FactoryBot.create(:pki_issued_certificate)
      cert.revoke!(reason: "key_compromise")

      expect(cert.reload.revoked?).to be true
      expect(cert.revocation_reason).to eq("key_compromise")
    end

    it "is idempotent - second call preserves original revoked_at" do
      cert = FactoryBot.create(:pki_issued_certificate)
      cert.revoke!
      original_revoked_at = cert.revoked_at

      travel 5.minutes do
        cert.revoke!
      end

      expect(cert.reload.revoked_at).to be_within(1.second).of(original_revoked_at)
    end
  end

  describe "scopes" do
    it "#active returns non-revoked, non-expired certs" do
      active  = FactoryBot.create(:pki_issued_certificate)
      revoked = FactoryBot.create(:pki_issued_certificate, :revoked)
      expired = FactoryBot.create(:pki_issued_certificate, :expired)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(revoked, expired)
    end

    it "#revoked returns only revoked certs" do
      active  = FactoryBot.create(:pki_issued_certificate)
      revoked = FactoryBot.create(:pki_issued_certificate, :revoked)

      expect(described_class.revoked).to include(revoked)
      expect(described_class.revoked).not_to include(active)
    end
  end

  describe "status predicates" do
    it "#active? is true for a live cert" do
      cert = FactoryBot.build(:pki_issued_certificate)
      expect(cert.active?).to be true
    end

    it "#revoked? is true when revoked_at is set" do
      cert = FactoryBot.build(:pki_issued_certificate, :revoked)
      expect(cert.revoked?).to be true
    end

    it "#expired? is true when past expires_at" do
      cert = FactoryBot.build(:pki_issued_certificate, :expired)
      expect(cert.expired?).to be true
    end
  end
end
