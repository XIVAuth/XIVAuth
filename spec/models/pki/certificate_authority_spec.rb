require "rails_helper"

RSpec.describe PKI::CertificateAuthority, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "validations" do
    it "requires slug" do
      ca = FactoryBot.build(:pki_certificate_authority, slug: nil)
      expect(ca).not_to be_valid
      expect(ca.errors[:slug]).to be_present
    end

    it "requires certificate_pem" do
      ca = FactoryBot.build(:pki_certificate_authority, certificate_pem: nil)
      expect(ca).not_to be_valid
      expect(ca.errors[:certificate_pem]).to be_present
    end

    it "requires private_key" do
      ca = FactoryBot.build(:pki_certificate_authority, private_key: nil)
      expect(ca).not_to be_valid
      expect(ca.errors[:private_key]).to be_present
    end

    it "enforces slug uniqueness" do
      FactoryBot.create(:pki_certificate_authority, slug: "unique-ca")
      ca = FactoryBot.build(:pki_certificate_authority, slug: "unique-ca")
      expect(ca).not_to be_valid
      expect(ca.errors[:slug]).to be_present
    end

    it "rejects slugs with uppercase letters" do
      ca = FactoryBot.build(:pki_certificate_authority, slug: "My-CA")
      expect(ca).not_to be_valid
      expect(ca.errors[:slug]).to be_present
    end

    it "accepts valid lowercase-alphanumeric-hyphen slugs" do
      ca = FactoryBot.build(:pki_certificate_authority, slug: "xivauth-root-2026")
      expect(ca).to be_valid
    end

    it "rejects a certificate without basicConstraints CA:TRUE (RFC 5280 §4.2.1.9)" do
      # Generate a leaf cert (no CA:TRUE)
      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.version    = 2
      cert.serial     = 1
      cert.subject    = OpenSSL::X509::Name.parse("CN=Not A CA")
      cert.issuer     = cert.subject
      cert.public_key = key
      cert.not_before = Time.now - 1
      cert.not_after  = Time.now + 10.years
      cert.sign(key, OpenSSL::Digest::SHA256.new)

      ca = FactoryBot.build(:pki_certificate_authority, certificate_pem: cert.to_pem, private_key: key.to_pem)
      expect(ca).not_to be_valid
      expect(ca.errors[:certificate_pem]).to include(match(/basicConstraints CA:TRUE/))
    end

    it "rejects a certificate without keyUsage keyCertSign (RFC 5280 §4.2.1.3)" do
      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.version    = 2
      cert.serial     = 1
      cert.subject    = OpenSSL::X509::Name.parse("CN=Bad CA")
      cert.issuer     = cert.subject
      cert.public_key = key
      cert.not_before = Time.now - 1
      cert.not_after  = Time.now + 10.years

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate  = cert
      cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
      # keyUsage with only digitalSignature - missing keyCertSign
      cert.add_extension(ef.create_extension("keyUsage", "digitalSignature", true))
      cert.sign(key, OpenSSL::Digest::SHA256.new)

      ca = FactoryBot.build(:pki_certificate_authority, certificate_pem: cert.to_pem, private_key: key.to_pem)
      expect(ca).not_to be_valid
      expect(ca.errors[:certificate_pem]).to include(match(/keyCertSign/))
    end

    it "rejects malformed PEM" do
      ca = FactoryBot.build(:pki_certificate_authority, certificate_pem: "not a cert")
      expect(ca).not_to be_valid
      expect(ca.errors[:certificate_pem]).to include(match(/not a valid X.509/))
    end
  end

  describe "#revoked?" do
    it "returns false when revoked_at is nil" do
      ca = FactoryBot.build(:pki_certificate_authority)
      expect(ca.revoked?).to be false
    end

    it "returns true when revoked_at is set" do
      ca = FactoryBot.build(:pki_certificate_authority, :revoked)
      expect(ca.revoked?).to be true
    end
  end

  describe "#revoke!" do
    it "sets revoked_at and deactivates" do
      ca = FactoryBot.create(:pki_certificate_authority)
      ca.revoke!(reason: "key_compromise")

      expect(ca.reload.revoked?).to be true
      expect(ca.active?).to be false
      expect(ca.revocation_reason).to eq("key_compromise")
    end

    it "is idempotent - second call preserves original revoked_at" do
      ca = FactoryBot.create(:pki_certificate_authority)
      ca.revoke!
      original_revoked_at = ca.revoked_at

      travel 5.minutes do
        ca.revoke!
      end

      expect(ca.reload.revoked_at).to be_within(1.second).of(original_revoked_at)
    end

    it "does not cascade to issued certificates" do
      ca = FactoryBot.create(:pki_certificate_authority)
      cert = FactoryBot.create(:pki_issued_certificate, certificate_authority: ca)

      ca.revoke!

      expect(cert.reload.revoked?).to be false
    end
  end

  describe ".current_for" do
    it "returns the most recently created active CA for the certificate type" do
      FactoryBot.create(:pki_certificate_authority, created_at: 2.days.ago)
      new_ca = FactoryBot.create(:pki_certificate_authority, created_at: 1.day.ago)

      expect(PKI::CertificateAuthority.current_for(certificate_type: "user_identification")).to eq(new_ca)
    end

    it "excludes inactive CAs" do
      FactoryBot.create(:pki_certificate_authority, :inactive)
      active_ca = FactoryBot.create(:pki_certificate_authority)

      expect(PKI::CertificateAuthority.current_for(certificate_type: "user_identification")).to eq(active_ca)
    end

    it "excludes revoked CAs" do
      FactoryBot.create(:pki_certificate_authority, :revoked)
      active_ca = FactoryBot.create(:pki_certificate_authority)

      expect(PKI::CertificateAuthority.current_for(certificate_type: "user_identification")).to eq(active_ca)
    end

    it "raises when no active CA exists for the certificate type" do
      expect {
        PKI::CertificateAuthority.current_for(certificate_type: "user_identification")
      }.to raise_error(PKI::CertificateAuthority::NoCertificateAuthorityError, /No active CA certificate for certificate type/)
    end
  end

  describe ".for_certificate_type scope" do
    it "returns CAs that include the given type" do
      ca_all   = FactoryBot.create(:pki_certificate_authority)
      ca_users = FactoryBot.create(:pki_certificate_authority, :user_identification_only)

      expect(PKI::CertificateAuthority.for_certificate_type("user_identification")).to include(ca_all, ca_users)
      expect(PKI::CertificateAuthority.for_certificate_type("character_identification")).to include(ca_all)
      expect(PKI::CertificateAuthority.for_certificate_type("character_identification")).not_to include(ca_users)
    end
  end

  describe "slug_immutable_after_issuance" do
    it "prevents changing the slug after certificates have been issued" do
      ca = FactoryBot.create(:pki_certificate_authority)
      FactoryBot.create(:pki_issued_certificate, certificate_authority: ca)

      ca.slug = "new-slug"
      expect(ca).not_to be_valid
      expect(ca.errors[:slug]).to include("cannot be changed after certificates have been issued")
    end

    it "allows changing the slug before any certs are issued" do
      ca = FactoryBot.create(:pki_certificate_authority)
      ca.slug = "new-slug"
      expect(ca).to be_valid
    end
  end
end
