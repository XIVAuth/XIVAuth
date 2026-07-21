require "utilities/crockford"

FactoryBot.define do
  factory :oauth_device_grant, class: "OAuth::DeviceGrant" do
    application factory: %i[oauth_client]
    user_code { Crockford.generate(length: 8) }
    expires_in { 600 }

    trait :expired do
      expires_in { -600 }
    end

    trait :claimed do
      user_code { nil }
      resource_owner factory: %i[user]
    end
  end
end
