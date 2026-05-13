FactoryBot.define do
  factory :users_profile, class: "User::Profile" do
    user { nil }  # profiles are always created within the context of a user, so set it to nil here.
    display_name { "TEST_#{Faker::Internet.username(specifier: 6..24)}" }
  end
end
