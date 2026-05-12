require_relative "../support/pki_support"

FactoryBot.define do
  factory :pki_issued_certificate, class: "PKI::IssuedCertificate" do
    # Generates a certificate *without* using shared keys, as that may muck up tests where we need multiple certs.
    # Speed-wise, this shouldn't be a problem as we use EC curves.
    # Certificate attributes (issued_at, expires_at, public_key_info, fingerprints) are derived
    # automatically when certificate_pem is assigned via the model's certificate_pem= setter.

    transient do
      cert_uuid { SecureRandom.uuid_v7 }

      # transients to allow overriding derived data for test purposes.
      # This allows us to pass in/override internal state data without needing to do certificate magic, which is very
      # annoying during testing.
      issued_at { nil }
      expires_at { nil }
      public_key_info { nil }
      certificate_fingerprint { nil }
      public_key_fingerprint { nil }
    end

    id { cert_uuid }
    certificate_authority { association :pki_certificate_authority }
    subject { association :user }
    certificate_type { "user_identification" }
    certificate_pem do
      serial = cert_uuid.delete("-").to_i(16)
      PkiSupport.generate_leaf_pem(
        certificate_authority.as_openssl_certificate, certificate_authority.as_openssl_pkey,
        common_name: "user:#{subject&.id || 'test'}", serial: serial
      )
    end

    trait :for_character_registration do
      subject { association :verified_registration }
      certificate_type { "character_identification" }
    end

    trait :code_signing do
      subject { association :user }
      certificate_type { "code_signing" }
    end

    trait :revoked do
      revoked_at { 1.day.ago }
      revocation_reason { "unspecified" }
    end

    trait :expired do
      issued_at { 2.years.ago }
      expires_at { 1.year.ago }
    end

    trait :renewable do
      issued_at { 10.months.ago }
      expires_at { 2.months.from_now }
    end

    after(:build) do |cert, evaluator|
      cert[:issued_at] = evaluator.issued_at if evaluator.issued_at
      cert[:expires_at] = evaluator.expires_at if evaluator.expires_at
      cert[:public_key_info] = evaluator.public_key_info if evaluator.public_key_info
      cert[:certificate_fingerprint] = evaluator.certificate_fingerprint if evaluator.certificate_fingerprint
      cert[:public_key_fingerprint] = evaluator.public_key_fingerprint if evaluator.public_key_fingerprint
    end
  end
end
