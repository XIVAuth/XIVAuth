FactoryBot.define do
  factory :client_application_acl, class: "ClientApplication::AccessControlList" do
    association :application, factory: :client_application
    association :principal, factory: :team

    deny { false }
    include_team_descendants { false }
  end
end
