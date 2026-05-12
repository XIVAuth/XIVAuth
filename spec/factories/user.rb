FactoryBot.define do
  factory :user do
    email { Faker::Internet.email(domain: "example.test") }
    password { Faker::Internet.password }
    confirmed_at { Time.current }
    webauthn_id { WebAuthn.generate_user_id }

    profile { association :users_profile, user: instance }

    trait :developer do
      roles { ["developer"] }
      totp_credential { association :users_totp_credential, user: instance, otp_enabled: true }
    end

    trait :passwordless do
      encrypted_password { nil }
      social_identities { [association(:users_social_identity, user: instance)] }
    end
  end
end
