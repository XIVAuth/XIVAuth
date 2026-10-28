FactoryBot.define do
  factory :users_totp_credential, class: "User::TotpCredential" do
    user
    otp_secret { ROTP::Base32.random }
    otp_enabled { false }

    # Real credentials always get backup codes on creation, and views assume they exist.
    after(:build) { |credential| credential.generate_otp_backup_codes! }

    trait :enabled do
      otp_enabled { true }
    end
  end
end
