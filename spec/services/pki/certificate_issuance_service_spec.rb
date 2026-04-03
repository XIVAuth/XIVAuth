require "rails_helper"

RSpec.describe PKI::CertificateIssuanceService, type: :service do
  let(:ca)      { FactoryBot.create(:pki_certificate_authority) }
  let(:user)    { FactoryBot.create(:user) }
  let(:ec_key)  { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:csr_pem) { PkiSupport.generate_csr_pem(key: ec_key) }

  subject(:service) { described_class.new(subject: user, certificate_type: "user_identification") }

  describe "#issue!" do
    context "with a valid CSR and user subject" do
      it "returns a persisted PKI::IssuedCertificate" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)

        expect(result).to be_a(PKI::IssuedCertificate)
        expect(result).to be_persisted
      end

      it "sets the correct subject" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        expect(result.subject).to eq(user)
      end

      it "sets the certificate_type" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        expect(result.certificate_type).to eq("user_identification")
      end

      it "the record id matches the certificate serial (round-trip)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        serial_int = result.id.delete("-").to_i(16)

        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        expect(cert.serial.to_i).to eq(serial_int)
      end

      it "ignores any subject fields from the CSR" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        expect(cert.subject.to_s).to include(user.display_name)
        expect(cert.subject.to_s).not_to include("Ignored By XIVAuth")
      end

      it "records public_key_fingerprint" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        expect(result.public_key_fingerprint).to start_with("sha256:")
      end

      it "sets requesting_application when provided" do
        app = FactoryBot.create(:client_application)
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca, requesting_application: app)
        expect(result.requesting_application).to eq(app)
      end

      it "embeds AIA and CRL URLs from default_url_options" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)

        url_extensions = cert.extensions.select { |e| %w[authorityInfoAccess crlDistributionPoints].include?(e.oid) }
        expect(url_extensions).not_to be_empty

        url_extensions.each do |ext|
          ext.value.scan(%r{https?://[^\s,]+}).each do |url|
            expect(url).to start_with("http://test.xivauth.net"),
              "Expected #{ext.oid} URL #{url.inspect} to start with http://test.xivauth.net"
          end
        end
      end

      it "embeds XIVAuth UserAuthentication EKU for user certificates (RFC 5280 §4.2.1.12)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)
        eku    = cert.extensions.find { |e| e.oid == "extendedKeyUsage" }

        expect(eku).not_to be_nil, "extendedKeyUsage extension must be present"
        expect(eku.value).to include(PKI::OID::EKU_UserIdentification)
      end

      it "embeds subjectAltName with user URI for user subjects (RFC 5280 §4.2.1.6)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)
        san    = cert.extensions.find { |e| e.oid == "subjectAltName" }

        expect(san).not_to be_nil, "subjectAltName extension must be present for user certs"
        expect(san.value).to include("urn:xivauth:user:#{user.id}")
      end

      it "works correctly with RSA keys" do
        rsa_csr = PkiSupport.generate_csr_pem(key: PkiSupport.shared_rsa_key)
        result  = service.issue!(csr_pem: rsa_csr, certificate_authority: ca)

        expect(result).to be_a(PKI::IssuedCertificate)
        expect(result).to be_persisted
        expect(result.key_type).to eq("RSA")
      end
    end

    context "with a valid CSR and character_registration subject" do
      let(:cr) { FactoryBot.create(:verified_registration) }
      let(:cr_service) { described_class.new(subject: cr, certificate_type: "character_identification") }

      it "embeds XIVAuth CharacterIdentification EKU for character certificates" do
        result = cr_service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)
        eku    = cert.extensions.find { |e| e.oid == "extendedKeyUsage" }

        expect(eku).not_to be_nil, "extendedKeyUsage extension must be present"
        expect(eku.value).to include(PKI::OID::EKU_CharacterIdentification)
      end

      it "embeds subjectAltName with lodestone and entangled_id URIs (RFC 5280 §4.2.1.6)" do
        result = cr_service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)
        san    = cert.extensions.find { |e| e.oid == "subjectAltName" }

        expect(san).not_to be_nil, "subjectAltName extension must be present for character certs"
        expect(san.value).to include("urn:xivauth:character:lodestone:#{cr.character.lodestone_id}")
        expect(san.value).to include("urn:xivauth:character:persistent_key:#{cr.entangled_id}")
      end
    end

    context "when the policy is invalid" do
      it "returns the policy with errors (no record written) for an EC curve not allowed" do
        weak_ec  = OpenSSL::PKey::EC.generate("secp112r1") rescue nil
        skip "secp112r1 not available" unless weak_ec
        weak_csr = PkiSupport.generate_csr_pem(key: weak_ec)

        expect {
          result = service.issue!(csr_pem: weak_csr, certificate_authority: ca)
          expect(result).to be_a(PKI::IssuancePolicy::Base)
          expect(result.errors[:public_key]).to be_present
        }.not_to change(PKI::IssuedCertificate, :count)
      end

      it "returns the policy with errors (no record written) for RSA key too small" do
        small_key = OpenSSL::PKey::RSA.new(1024)
        small_csr = PkiSupport.generate_csr_pem(key: small_key)

        expect {
          result = service.issue!(csr_pem: small_csr, certificate_authority: ca)
          expect(result).to be_a(PKI::IssuancePolicy::Base)
          expect(result.errors[:public_key]).to be_present
        }.not_to change(PKI::IssuedCertificate, :count)
      end

      it "returns the policy with errors for inactive CA" do
        inactive_ca = FactoryBot.create(:pki_certificate_authority, :inactive)
        result = service.issue!(csr_pem: csr_pem, certificate_authority: inactive_ca)

        expect(result).to be_a(PKI::IssuancePolicy::Base)
        expect(result.errors[:certificate_authority]).to be_present
      end

      it "raises NoCertificateAuthorityError when no CA exists for certificate type" do
        # Destroy all CAs so none are available
        PKI::CertificateAuthority.destroy_all

        expect {
          service.issue!(csr_pem: csr_pem)
        }.to raise_error(PKI::CertificateAuthority::NoCertificateAuthorityError, /No active CA certificate for certificate type/)
      end
    end

    context "with an invalid CSR" do
      it "raises IssuanceError for malformed PEM" do
        expect {
          service.issue!(csr_pem: "not a csr", certificate_authority: ca)
        }.to raise_error(PKI::CertificateIssuanceService::IssuanceError, /Invalid CSR/)
      end

      it "raises IssuanceError when CSR signature doesn't match its public key" do
        # Build a CSR with one key, then re-sign with a different key so the
        # embedded public key and the signature don't match.
        legit_key  = OpenSSL::PKey::EC.generate("prime256v1")
        tampered_key = OpenSSL::PKey::EC.generate("prime256v1")

        req = OpenSSL::X509::Request.new
        req.version    = 0
        req.subject    = OpenSSL::X509::Name.parse("CN=Tampered")
        req.public_key = legit_key  # embed legit_key's public key
        req.sign(tampered_key, OpenSSL::Digest::SHA256.new)  # but sign with a different key

        expect {
          service.issue!(csr_pem: req.to_pem, certificate_authority: ca)
        }.to raise_error(PKI::CertificateIssuanceService::IssuanceError, /CSR self-signature verification failed/)
      end
    end

    # These tests assert RFC 5280 structural requirements that are effectively guaranteed
    # by the certificate_authority gem and OpenSSL. They exist purely to claim compliance
    # and should never reasonably fail given how the code is architected.
    context "RFC 5280 compliance nitpicks", :compliance do
      it "is a version 3 (X.509 v3) certificate" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        expect(cert.version).to eq(2)  # OpenSSL uses 0-indexed version: 2 == v3
      end

      it "embeds authorityKeyIdentifier (RFC 5280 §4.2.1.1 MUST)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        aki = cert.extensions.find { |e| e.oid == "authorityKeyIdentifier" }
        expect(aki).not_to be_nil, "authorityKeyIdentifier extension must be present"
      end

      it "embeds subjectKeyIdentifier (RFC 5280 §4.2.1.2 SHOULD)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        ski = cert.extensions.find { |e| e.oid == "subjectKeyIdentifier" }
        expect(ski).not_to be_nil, "subjectKeyIdentifier extension should be present"
      end

      it "marks basicConstraints CA=false as critical (RFC 5280 §4.2.1.9)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        bc = cert.extensions.find { |e| e.oid == "basicConstraints" }

        expect(bc).not_to be_nil, "basicConstraints extension must be present"
        expect(bc.critical?).to be(true), "basicConstraints must be critical"
        expect(bc.value).to include("CA:FALSE")
      end

      it "marks keyUsage as critical (RFC 5280 §4.2.1.3)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert = OpenSSL::X509::Certificate.new(result.certificate_pem)
        ku = cert.extensions.find { |e| e.oid == "keyUsage" }

        expect(ku).not_to be_nil, "keyUsage extension must be present"
        expect(ku.critical?).to be(true), "keyUsage must be critical"
      end

      it "sets issuer DN to match the CA's subject DN (RFC 5280 §4.1.2.4)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert    = OpenSSL::X509::Certificate.new(result.certificate_pem)
        ca_cert = OpenSSL::X509::Certificate.new(ca.certificate_pem)

        expect(cert.issuer.to_s).to eq(ca_cert.subject.to_s)
      end

      it "produces a positive serial number no longer than 20 octets (RFC 5280 §4.1.2.2)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)

        serial_bytes = cert.serial.to_s(2)
        expect(serial_bytes.bytesize).to be <= 20,
                                         "serial is #{serial_bytes.bytesize} octets, RFC 5280 §4.1.2.2 limits to 20"

        expect(cert.serial).to be > 0, "serial must be positive"
      end

      it "has notBefore < notAfter and they match the DB record (RFC 5280 §4.1.2.5)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)

        expect(cert.not_before).to be < cert.not_after
        expect(cert.not_before).to be_within(1.seconds).of(result.issued_at)
        expect(cert.not_after).to be_within(1.seconds).of(result.expires_at)
      end

      it "uses a consistent signature algorithm (RFC 5280 §4.1.1.2)" do
        result = service.issue!(csr_pem: csr_pem, certificate_authority: ca)
        cert   = OpenSSL::X509::Certificate.new(result.certificate_pem)

        expect(cert.signature_algorithm).to be_present
        # For an EC CA key, expect an ECDSA algorithm
        expect(cert.signature_algorithm).to match(/ecdsa/i)
      end

    end
  end
end
