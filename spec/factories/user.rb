FactoryBot.define do
  factory :user do
    # Plain Faker::Internet.email isn't deduplicated, so across a full suite run
    # it can (rarely) collide and trip Devise's email-uniqueness validation.
    # The sequence guarantees uniqueness outright.
    sequence(:email) { |n| "#{Faker::Internet.username(specifier: 6..12)}.#{n}@example.test" }
    password { Faker::Internet.password }
    confirmed_at { Time.current }
    webauthn_id { WebAuthn.generate_user_id }

    # strategy: :build (not the default :create) leaves these unsaved and lets
    # the has_one/has_many autosave persist them after `instance` itself is
    # saved and has an id. Eagerly creating them (the old behavior) races
    # belongs_to's silent (non-raising) autosave of `instance` — if that save
    # ever fails validation, the nested record gets inserted with a nil FK.
    profile { association :users_profile, user: instance, strategy: :build }

    trait :developer do
      roles { ["developer"] }
      totp_credential { association :users_totp_credential, user: instance, otp_enabled: true, strategy: :build }
    end

    trait :passwordless do
      encrypted_password { nil }
      social_identities { [association(:users_social_identity, user: instance, strategy: :build)] }
    end
  end
end
