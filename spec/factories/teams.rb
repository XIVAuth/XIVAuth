FactoryBot.define do
  factory :team do
    sequence(:name) { |n| "Team #{n}" }
    inherit_parent_memberships { true }

    transient do
      skip_initial_admin { false }
    end

    trait :no_initial_admin do
      skip_initial_admin { true }
    end

    trait :no_inherit do
      inherit_parent_memberships { false }
    end

    trait :with_parent do
      parent factory: %i[team]
    end

    # Ensure root teams have at least one admin via nested attributes
    after(:build) do |team, evaluator|
      # Only apply to root teams (no parent)
      next if team.parent.present?
      next if evaluator.skip_initial_admin

      # Check in-memory memberships to respect unsaved built associations
      has_admin = team.direct_memberships.any? { |m| m.role.to_s == "admin" }
      next if has_admin

      admin_user = FactoryBot.create(:user)
      team.direct_memberships.build(user: admin_user, role: "admin")
    end
  end
end
