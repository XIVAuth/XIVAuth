require "rails_helper"

RSpec.describe "Users::OAuthAuthorizationsController" do
  let(:user) { FactoryBot.create(:user) }
  let(:oauth_client) { FactoryBot.create(:oauth_client) }

  before { sign_in user }

  describe "DELETE /user/authorizations/:id" do
    it "revokes the selected application's tokens and grants for the current user" do
      authorization = create_token(user:, application: oauth_client)
      sibling_token = create_token(user:, application: oauth_client)
      access_grant = create_grant(user:, application: oauth_client)
      other_user_token = create_token(user: FactoryBot.create(:user), application: oauth_client)

      delete user_oauth_authorization_path(authorization)

      expect(response).to redirect_to(user_oauth_authorizations_path)
      expect(authorization.reload).to be_revoked
      expect(sibling_token.reload).to be_revoked
      expect(access_grant.reload).to be_revoked
      expect(other_user_token.reload).not_to be_revoked
    end

    it "preserves the current user's authorizations for other applications" do
      authorization = create_token(user:, application: oauth_client)
      other_token = create_token(user:, application: FactoryBot.create(:oauth_client))

      delete user_oauth_authorization_path(authorization)

      expect(other_token.reload).not_to be_revoked
    end

    it "does not let the current user revoke another user's authorization" do
      other_user = FactoryBot.create(:user)
      other_token = create_token(user: other_user, application: oauth_client)

      expect do
        delete user_oauth_authorization_path(other_token)
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect(other_token.reload).not_to be_revoked
    end
  end

  def create_token(user:, application:)
    OAuth::AccessToken.create!(
      application:,
      resource_owner: user,
      scopes: "user",
      refresh_token: SecureRandom.hex(32)
    )
  end

  def create_grant(user:, application:)
    OAuth::AccessGrant.create!(
      application:,
      resource_owner: user,
      expires_in: 10.minutes,
      redirect_uri: "https://client.example/callback",
      scopes: "user",
      token: SecureRandom.hex(32)
    )
  end
end
