require "rails_helper"

RSpec.describe "OAuth::DeviceAuthorizationsController" do
  let(:user) { FactoryBot.create(:user) }

  before { sign_in user }

  describe "POST /oauth/device" do
    context "when the device grant does not exist" do
      it "redirects to the index page" do
        post "/oauth/device", params: { user_code: "AAAA-AAAA" }
        expect(response).to redirect_to(oauth_device_authorizations_index_url)
      end
    end

    context "when the device grant has expired" do
      let(:device_grant) { FactoryBot.create(:oauth_device_grant, :expired) }

      it "redirects to the index page" do
        post "/oauth/device", params: { user_code: device_grant.user_code }
        expect(response).to redirect_to(oauth_device_authorizations_index_url)
      end
    end

    context "when denying a device grant that does not exist" do
      it "redirects to the index page" do
        post "/oauth/device", params: { user_code: "AAAA-AAAA", disposition: "deny" }
        expect(response).to redirect_to(oauth_device_authorizations_index_url)
      end
    end

    context "when denying an existing device grant" do
      let(:device_grant) { FactoryBot.create(:oauth_device_grant) }

      it "revokes the grant and redirects" do
        post "/oauth/device", params: { user_code: device_grant.user_code, disposition: "deny" }

        expect(response).to redirect_to(oauth_device_authorizations_index_url)
        expect(device_grant.reload.expires_in).to eq(0)
      end
    end

    context "when authorizing a valid device grant" do
      let(:device_grant) { FactoryBot.create(:oauth_device_grant) }

      it "authorizes the grant and redirects to the completion path" do
        post "/oauth/device", params: { user_code: device_grant.user_code }

        expect(response).to redirect_to(oauth_device_authorizations_complete_path)
        expect(device_grant.reload.resource_owner).to eq(user)
      end
    end
  end
end
