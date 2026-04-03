require "rails_helper"

RSpec.describe PKI::IssuancePolicy, type: :model do
  let(:ca)      { FactoryBot.create(:pki_certificate_authority) }
  let(:user)    { FactoryBot.create(:user) }
  let(:ec_key)  { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:rsa_key) { PkiSupport.shared_rsa_key }

  # Default policy uses EC - fast for the bulk of tests.
  def build_policy(certificate_type: "user_identification", subject: user, public_key: ec_key, ca: self.ca, requesting_application: nil)
    PKI::IssuancePolicy.for(
      certificate_type: certificate_type, subject: subject, public_key: public_key,
      certificate_authority: ca, requesting_application: requesting_application
    )
  end

  describe ".for factory" do
    it "returns UserIdentificationPolicy for user_identification type" do
      expect(build_policy).to be_a(PKI::IssuancePolicy::UserIdentificationPolicy)
    end

    it "returns CharacterIdentificationPolicy for character_identification type" do
      cr = FactoryBot.create(:verified_registration)
      policy = build_policy(certificate_type: "character_identification", subject: cr)
      expect(policy).to be_a(PKI::IssuancePolicy::CharacterIdentificationPolicy)
    end

    it "returns CodeSigningPolicy for code_signing type" do
      policy = build_policy(certificate_type: "code_signing",
                            ca: FactoryBot.create(:pki_certificate_authority, :code_signing_only))
      expect(policy).to be_a(PKI::IssuancePolicy::CodeSigningPolicy)
    end

    it "raises for unknown certificate types" do
      expect {
        PKI::IssuancePolicy.for(certificate_type: "unknown", subject: user, public_key: ec_key, certificate_authority: ca)
      }.to raise_error(ArgumentError, /No PKI issuance policy/)
    end
  end

  describe "subject type validation" do
    it "rejects a subject type not allowed for the certificate type" do
      cr = FactoryBot.create(:verified_registration)
      policy = build_policy(certificate_type: "user_identification", subject: cr)
      expect(policy).not_to be_valid
      expect(policy.errors[:subject]).to be_present
    end
  end

  describe "key type validation" do
    it "is valid for EC keys on an allowed curve (default)" do
      expect(build_policy).to be_valid
    end

    it "is valid for RSA keys" do
      expect(build_policy(public_key: rsa_key)).to be_valid
    end
  end

  describe "key strength validation" do
    it "rejects RSA keys below 2048 bits" do
      small_key = OpenSSL::PKey::RSA.new(1024)
      policy = build_policy(public_key: small_key)

      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/RSA key too small/))
    end

    it "rejects EC keys on disallowed curves" do
      weak_ec = OpenSSL::PKey::EC.generate("secp112r1") rescue nil
      skip "secp112r1 not available" unless weak_ec

      policy = build_policy(public_key: weak_ec)
      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/EC curve not allowed/))
    end
  end

  describe "CA validation" do
    it "rejects inactive CA" do
      inactive_ca = FactoryBot.create(:pki_certificate_authority, :inactive)
      expect(build_policy(ca: inactive_ca)).not_to be_valid
    end

    it "rejects revoked CA" do
      revoked_ca = FactoryBot.create(:pki_certificate_authority, :revoked)
      expect(build_policy(ca: revoked_ca)).not_to be_valid
    end

    it "rejects CA not permitted for the certificate type" do
      users_only_ca = FactoryBot.create(:pki_certificate_authority, :user_identification_only)
      cr = FactoryBot.create(:verified_registration)
      policy = build_policy(certificate_type: "character_identification", subject: cr, ca: users_only_ca)

      expect(policy).not_to be_valid
      expect(policy.errors[:certificate_authority]).to be_present
    end
  end

  describe "certificate limit validation" do
    it "rejects issuance when limit is reached" do
      FactoryBot.create_list(:pki_issued_certificate, 2, subject: user, certificate_authority: ca,
                  requesting_application_id: nil)

      expect(build_policy).not_to be_valid
    end

    it "counts limits separately per requesting application" do
      app1 = FactoryBot.create(:client_application)
      app2 = FactoryBot.create(:client_application)
      FactoryBot.create_list(:pki_issued_certificate, 2, subject: user, certificate_authority: ca,
                  requesting_application: app1)

      policy = build_policy(requesting_application: app2)
      expect(policy).to be_valid
    end
  end

  describe "keyUsage and EKU for UserIdentificationPolicy" do
    it "uses digitalSignature only for EC keys" do
      usage = build_policy(public_key: ec_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to eq(%w[digitalSignature])
    end

    it "uses digitalSignature only for RSA keys" do
      usage = build_policy(public_key: rsa_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to eq(%w[digitalSignature])
    end

    it "uses XIVAuth's UserIdentification EKU" do
      eku = build_policy.signing_profile["extensions"]["extendedKeyUsage"]["usage"]
      expect(eku).to eq(%w[1.3.6.1.4.1.65394.10.3.2])
    end
  end

  describe "keyUsage and EKU for CharacterIdentificationPolicy" do
    let(:cr) { FactoryBot.create(:verified_registration) }

    def build_cr_policy(public_key: ec_key)
      build_policy(certificate_type: "character_identification", subject: cr, public_key: public_key)
    end

    it "includes digitalSignature and keyAgreement for EC" do
      usage = build_cr_policy(public_key: ec_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to include("digitalSignature", "keyAgreement")
      expect(usage).not_to include("keyEncipherment")
    end

    it "includes digitalSignature and keyEncipherment for RSA" do
      usage = build_cr_policy(public_key: rsa_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to include("digitalSignature", "keyEncipherment")
      expect(usage).not_to include("keyAgreement")
    end

    it "uses XIVAuth's UserIdentification EKU" do
      eku = build_cr_policy.signing_profile["extensions"]["extendedKeyUsage"]["usage"]
      expect(eku).to eq(%w[1.3.6.1.4.1.65394.10.3.1])
    end
  end

  describe "keyUsage and EKU for CodeSigningPolicy" do
    def build_cs_policy(public_key: ec_key)
      build_policy(certificate_type: "code_signing", subject: user, public_key: public_key)
    end

    it "uses digitalSignature only for EC keys" do
      usage = build_cs_policy(public_key: ec_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to eq(%w[digitalSignature])
    end

    it "uses digitalSignature only for RSA keys" do
      usage = build_cs_policy(public_key: rsa_key).signing_profile["extensions"]["keyUsage"]["usage"]
      expect(usage).to eq(%w[digitalSignature])
    end

    it "uses clientAuth EKU" do
      eku = build_cs_policy.signing_profile["extensions"]["extendedKeyUsage"]["usage"]
      expect(eku).to eq(%w[codeSigning])
    end
  end

  describe "revoked key validation" do
    let(:revoked_key)         { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:revoked_fingerprint) { "sha256:#{OpenSSL::Digest::SHA256.hexdigest(revoked_key.to_der)}" }

    it "rejects a key that was used in a revoked certificate" do
      FactoryBot.create(:pki_issued_certificate, :revoked, subject: user, certificate_authority: ca,
                        public_key_fingerprint: revoked_fingerprint)
      policy = build_policy(public_key: revoked_key)

      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/has been revoked/))
    end

    it "allows a fresh key even when the same subject has a revoked cert under a different key" do
      FactoryBot.create(:pki_issued_certificate, :revoked, subject: user, certificate_authority: ca)
      expect(build_policy(public_key: OpenSSL::PKey::EC.generate("prime256v1"))).to be_valid
    end

  end

  describe "key subject uniqueness validation" do
    # Each test here needs a cert with a known fingerprint plus a policy using the same
    # key, so we generate a fresh EC key rather than the shared outer let.
    let(:fresh_key)         { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:fresh_fingerprint) { "sha256:#{OpenSSL::Digest::SHA256.hexdigest(fresh_key.to_der)}" }

    it "allows the same key to be reused for the same subject when in the renewal window" do
      FactoryBot.create(:pki_issued_certificate, :renewable, subject: user, certificate_authority: ca,
                        public_key_fingerprint: fresh_fingerprint)
      policy = build_policy(subject: user, public_key: fresh_key)

      expect(policy).to be_valid
    end

    it "rejects a key already used for a different user" do
      other_user = FactoryBot.create(:user)
      FactoryBot.create(:pki_issued_certificate, subject: other_user, certificate_authority: ca,
                        public_key_fingerprint: fresh_fingerprint)
      policy = build_policy(subject: user, public_key: fresh_key)

      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/already associated with a different subject/))
    end

    it "rejects a key already used for a different subject type (user → character)" do
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca,
                        public_key_fingerprint: fresh_fingerprint)
      cr     = FactoryBot.create(:verified_registration)
      policy = build_policy(certificate_type: "character_identification", subject: cr, public_key: fresh_key)

      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/already associated with a different subject/))
    end

    it "allows a fresh key even when the subject already has certs under a different key" do
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca)
      policy = build_policy(subject: user, public_key: ec_key)

      expect(policy).to be_valid
    end

    it "rejects a key already used by the same subject under a different certificate type" do
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca,
                        certificate_type: "user_identification",
                        public_key_fingerprint: fresh_fingerprint)
      policy = build_policy(certificate_type: "code_signing", subject: user, public_key: fresh_key,
                            ca: FactoryBot.create(:pki_certificate_authority, :code_signing_only))

      expect(policy).not_to be_valid
      expect(policy.errors[:public_key]).to include(match(/already associated with a different subject/))
    end
  end

  describe "renewal window validation" do
    let(:renewal_key)         { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:renewal_fingerprint) { "sha256:#{OpenSSL::Digest::SHA256.hexdigest(renewal_key.to_der)}" }

    it "allows first issuance with a fresh key regardless of timing" do
      expect(build_policy(public_key: renewal_key)).to be_valid
    end

    it "allows renewal when 75% of a 1-year cert's life has elapsed" do
      FactoryBot.create(:pki_issued_certificate, :renewable, subject: user, certificate_authority: ca,
                        public_key_fingerprint: renewal_fingerprint)
      expect(build_policy(public_key: renewal_key)).to be_valid
    end

    it "allows renewal when over 1 year has passed on a long-lived cert" do
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca,
                        public_key_fingerprint: renewal_fingerprint,
                        issued_at: 13.months.ago, expires_at: 11.months.from_now)
      expect(build_policy(public_key: renewal_key)).to be_valid
    end

    it "blocks renewal when less than 75% of a 1-year cert's life has elapsed" do
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca,
                        public_key_fingerprint: renewal_fingerprint,
                        issued_at: 3.months.ago, expires_at: 9.months.from_now)
      policy = build_policy(public_key: renewal_key)

      expect(policy).not_to be_valid
      expect(policy.errors[:base]).to include(match(/not yet eligible for renewal/))
    end

    it "does not apply the renewal window when using a new key" do
      # Existing cert under a different key should not trigger renewal window
      FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: ca,
                        issued_at: 1.day.ago, expires_at: 1.year.from_now)
      expect(build_policy(public_key: renewal_key)).to be_valid
    end
  end

  describe "CharacterIdentificationPolicy" do
    let(:cr)          { FactoryBot.create(:verified_registration) }
    let(:cr_key)      { OpenSSL::PKey::EC.generate("prime256v1") }
    let(:cr_key_fp)   { "sha256:#{OpenSSL::Digest::SHA256.hexdigest(cr_key.to_der)}" }

    def build_cr_policy(subject: cr, public_key: cr_key)
      build_policy(certificate_type: "character_identification", subject: subject, public_key: public_key)
    end

    it "rejects unverified CharacterRegistration" do
      unverified = FactoryBot.create(:character_registration)
      policy = build_cr_policy(subject: unverified)

      expect(policy).not_to be_valid
      expect(policy.errors[:subject]).to include(match(/must be verified/))
    end
  end

  describe "API access via ClientAppAbility" do
    let(:app_with_entitlement) { FactoryBot.create(:client_application, entitlements: ["code_signing_certificates"]) }
    let(:app_without_entitlement) { FactoryBot.create(:client_application, entitlements: []) }

    it "allows any app to issue user_identification certificates" do
      ability = Abilities::ClientAppAbility.new(app_without_entitlement)
      expect(ability.can?(:issue, PKI::IssuancePolicy::UserIdentificationPolicy)).to be true
    end

    it "allows any app to revoke user_identification certificates" do
      ability = Abilities::ClientAppAbility.new(app_without_entitlement)
      expect(ability.can?(:revoke, PKI::IssuancePolicy::UserIdentificationPolicy)).to be true
    end

    it "allows any app to issue character_identification certificates" do
      ability = Abilities::ClientAppAbility.new(app_without_entitlement)
      expect(ability.can?(:issue, PKI::IssuancePolicy::CharacterIdentificationPolicy)).to be true
    end

    it "allows any app to revoke character_identification certificates" do
      ability = Abilities::ClientAppAbility.new(app_without_entitlement)
      expect(ability.can?(:revoke, PKI::IssuancePolicy::CharacterIdentificationPolicy)).to be true
    end

    it "denies code_signing without entitlement" do
      ability = Abilities::ClientAppAbility.new(app_without_entitlement)
      expect(ability.can?(:issue, PKI::IssuancePolicy::CodeSigningPolicy)).to be false
      expect(ability.can?(:revoke, PKI::IssuancePolicy::CodeSigningPolicy)).to be false
    end

    it "allows code_signing with entitlement" do
      ability = Abilities::ClientAppAbility.new(app_with_entitlement)
      expect(ability.can?(:issue, PKI::IssuancePolicy::CodeSigningPolicy)).to be true
      expect(ability.can?(:revoke, PKI::IssuancePolicy::CodeSigningPolicy)).to be true
    end
  end
end
