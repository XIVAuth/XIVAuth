FactoryBot.define do
  factory :oauth_client, class: "ClientApplication::OAuthClient" do
    application factory: %i[client_application]

    name { "OAuth Client #{SecureRandom.hex(4)}" }
    enabled { true }

    client_id { SecureRandom.hex(16) }
    client_secret { SecureRandom.hex(32) }

    # Keep flows minimal for tests; allows blank redirect_uris per initializer
    grant_flows { ["client_credentials"] }
    redirect_uris { [] }
    confidential { true }
  end
end
