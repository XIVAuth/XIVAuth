json.extract! social_identity, :provider, :external_id, :name, :nickname

json.extract! social_identity, :email if @doorkeeper_token.scopes.exists?("user:email")

json.extract! social_identity, :created_at, :updated_at
