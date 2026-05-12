FactoryBot.define do
  factory :client_application_acl, class: "ClientApplication::AccessControlList" do
    application factory: %i[client_application]
    principal factory: %i[team]

    deny { false }
    include_team_descendants { false }
  end
end
