FactoryBot.define do
  factory :users_webauthn_credential, class: "User::WebauthnCredential" do
    user
    external_id { SecureRandom.uuid }
    public_key { Base64.strict_encode64(SecureRandom.random_bytes(65)) }
    nickname { "#{Faker::Device.manufacturer} #{Faker::Device.model_name}" }
    sign_count { 0 }

    trait :security_key do
      nickname { "Security Key" }
    end

    trait :platform_authenticator do
      nickname { "#{Faker::Device.platform} Passkey" }
    end
  end
end
