require "rails_helper"

RSpec.describe Users::OmniauthCallbacksController, type: :controller do
  # Note: not configured in test environment, so we'll hack these in.
  before(:all) do
    %i[discord steam].each do |provider|
      next if described_class.method_defined?(provider)

      described_class.define_method(provider) do
        @provider = provider
        common
      end
    end
  end

  # As the test env doesn't load SSO configurations, just make some up.
  routes do
    ActionDispatch::Routing::RouteSet.new.tap do |set|
      set.draw do
        devise_scope :user do
          post "/test_sso/discord", to: "users/omniauth_callbacks#discord"
          post "/test_sso/steam", to: "users/omniauth_callbacks#steam"
        end
      end
    end
  end

  let(:provider) { "discord" }
  let(:uid) { "1234567890" }
  let(:email) { "newcomer@example.test" }
  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: provider,
      uid: uid,
      info: { email: email, name: "Test Name", nickname: "tester" },
      extra: { raw_info: { "id" => uid } }
    )
  end

  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @request.env["omniauth.auth"] = auth_hash

    allow(User).to receive_messages(omniauth_providers: %i[discord steam], omniauth_login_providers: %i[discord steam])
    Flipper.enable(:user_signups)
  end

  def app_routes = Rails.application.routes.url_helpers

  def callback!(action = provider)
    post action.to_sym
  end

  context "when the identity is already linked" do
    let!(:user) { FactoryBot.create(:user) }
    let!(:identity) do
      FactoryBot.create(:users_social_identity, user: user, provider: provider, external_id: uid, name: "Old Name",
                                     last_used_at: nil)
    end

    it "signs in the owning user" do
      callback!

      expect(controller.current_user).to eq(user)
    end

    it "refreshes the identity and marks it as used" do
      callback!

      identity.reload
      expect(identity.name).to eq("Test Name")
      expect(identity.last_used_at).to be_within(1.minute).of(Time.current)
    end

    it "does not create another user" do
      expect { callback! }.not_to change(User, :count)
    end
  end

  context "when the identity is unknown" do
    context "and no account has the provider's email" do
      it "registers a new user with the identity and signs them in" do
        expect { callback! }.to change(User, :count).by(1).and change(User::SocialIdentity, :count).by(1)

        expect(controller.current_user.email).to eq(email)
        expect(controller.current_user.social_identities.pluck(:provider, :external_id)).to eq([[provider, uid]])
      end

      it "refuses to register when sign-ups are disabled" do
        Flipper.disable(:user_signups)

        expect { callback! }.not_to change(User, :count)

        expect(response).to redirect_to(app_routes.new_user_session_path)
        expect(flash[:alert]).to match(/sign-ups are disabled/i)
        expect(controller.current_user).to be_nil
      end
    end

    context "and an account without MFA has the provider's email" do
      let!(:user) { FactoryBot.create(:user, email: email) }

      it "binds the identity to that account and signs in" do
        expect { callback! }.not_to change(User, :count)

        expect(controller.current_user).to eq(user)
        expect(user.social_identities.reload.pluck(:provider, :external_id)).to eq([[provider, uid]])
      end

      it "matches the email case-insensitively" do
        auth_hash.info.email = email.upcase

        callback!

        expect(controller.current_user).to eq(user)
      end

      it "binds even when sign-ups are disabled" do
        Flipper.disable(:user_signups)

        callback!

        expect(controller.current_user).to eq(user)
      end

      it "rejects the login when the bind cannot be saved" do
        allow_any_instance_of(User).to receive(:save).and_return(false) # rubocop:disable RSpec/AnyInstance

        callback!

        expect(response).to redirect_to(app_routes.new_user_session_path)
        expect(controller.current_user).to be_nil
        expect(User::SocialIdentity.where(external_id: uid)).to be_empty
      end
    end

    context "and an account with MFA has the provider's email" do
      let!(:user) { FactoryBot.create(:user, email: email) }

      before { FactoryBot.create(:users_totp_credential, :enabled, user: user) }

      it "blocks the login without binding the identity" do
        expect { callback! }.not_to change(User::SocialIdentity, :count)

        expect(response).to redirect_to(app_routes.new_user_session_path)
        expect(flash[:alert]).to match(/must link your Discord account/i)
        expect(controller.current_user).to be_nil
      end

      it "blocks the login even when sign-ups are disabled" do
        Flipper.disable(:user_signups)

        callback!

        expect(flash[:alert]).to match(/must link your Discord account/i)
        expect(controller.current_user).to be_nil
      end
    end

    context "and the provider returns no email (e.g. steam)" do
      let(:provider) { "steam" }
      let(:email) { nil }

      it "requires the identity to be linked first, without creating or binding anything" do
        expect { callback! }.not_to change { [User.count, User::SocialIdentity.count] }

        expect(response).to redirect_to(app_routes.new_user_session_path)
        expect(flash[:alert]).to match(/must link your Steam account/i)
        expect(controller.current_user).to be_nil
      end
    end
  end
end
