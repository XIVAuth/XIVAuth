FactoryBot.define do
  factory :ffxiv_character, class: "FFXIV::Character" do
    lodestone_id { Faker::Number.unique.number(digits: 8) }
    # Faker::Games::Touhou.character only has ~110 distinct values, so across a
    # full suite run name collisions are near-guaranteed (birthday paradox) —
    # the sequence suffix guarantees uniqueness without risking Faker's .unique
    # retry-limit exhaustion once more than ~110 characters get created.
    sequence(:name) { |n| "#{Faker::Games::Touhou.character} #{n}" }
    home_world { Faker::Games::DnD.city }
    data_center { Faker::Books::Dune.planet }
    avatar_url { "https://picsum.photos/seed/#{lodestone_id}/96/96" }
    portrait_url { "https://picsum.photos/seed/#{lodestone_id}/640/873" }
  end
end
