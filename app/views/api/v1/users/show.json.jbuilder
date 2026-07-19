json.extract! @user, :id, :display_name

if @doorkeeper_token.scopes.exists?("user:email")
  json.email @user.email
  json.email_verified @user.confirmed_at.present? # basically always true
end

if @social_identities.present?
  json.social_identities @social_identities, partial: "api/v1/users/social_identity", as: "social_identity"
end

json.avatar_url Users::ApiAvatarResolver.new(@doorkeeper_token).resolve

json.mfa_enabled @user.mfa_enabled_or_passwordless?
json.verified_characters @user.verified_characters_present?

json.created_at @user.created_at
json.updated_at @user.updated_at
