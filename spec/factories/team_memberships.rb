FactoryBot.define do
  factory :team_membership, class: "Team::Membership" do
    association :team
    association :user
    role { "member" }

    trait :admin do
      role { "admin" }
    end

    trait :manager do
      role { "manager" }
    end

    trait :developer do
      role { "developer" }
    end

    trait :invited do
      role { "invited" }
    end

    trait :blocked do
      role { "blocked" }
    end
  end
end
