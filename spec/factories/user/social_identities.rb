FactoryBot.define do
  factory :users_social_identity, class: "User::SocialIdentity" do
    user
    provider { "discord" }
    external_id { Faker::Number.number(digits: 18).to_s }
    name { Faker::Internet.username }
    nickname { Faker::Internet.username }
    email { Faker::Internet.email(domain: "example.test") }

    trait :dummy do
      provider { "dummy" }
      external_id { Faker::Number.number(digits: 18).to_s }
    end

    trait :steam do
      provider { "steam" }
      external_id { Faker::Number.number(digits: 17).to_s }
    end

    trait :with_tokens do
      access_token { SecureRandom.hex(32) }
      refresh_token { SecureRandom.hex(32) }
    end

    trait :recently_used do
      last_used_at { 1.day.ago }
    end
  end
end
