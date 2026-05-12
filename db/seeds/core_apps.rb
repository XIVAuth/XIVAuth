# Seed file describing XIVAuth core teams, apps, and services.
# It's generally a good idea to make sure these exist, since certain app components need them.

internal_team = Team.find_or_initialize_by(id: "00000000-0000-8000-8f0f-000000000001") do |t|
  t.name = "XIVAuth Developers"
end
internal_team.save(validate: false) unless internal_team.persisted?

internal_app = ClientApplication.find_or_create_by!(id: "00000000-0000-8000-8f0f-00002c000001") do |app|
  app.name = "XIVAuth"
  app.owner = internal_team
  app.private = false

  app.verified_at = Time.current

  app.profile.homepage_url = "https://xivauth.net/"
  app.profile.privacy_policy_url = "https://xivauth.net/privacy"
  app.profile.terms_of_service_url = "https://xivauth.net/terms"
end

internal_app.oauth_clients.find_or_create_by!(client_id: "xivauth") do |client|
  client.id = "00000000-0000-8000-8f0f-00004e000001"
  client.name = "XIVAuth"

  # NOTE: Client secret is not defined and will be randomly generated.
  #       This is by design, since this OAuth client is an internal placeholder.

  client.confidential = true
  client.enabled = false
end
