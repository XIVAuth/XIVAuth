require "rails_helper"

RSpec.describe "OAuth::TokensController" do
  shared_examples "cross-origin POST request" do
    it "allows cross-origin requests" do
      expect(response.headers["Access-Control-Allow-Origin"]).to eq "*"
      expect(response.headers["Access-Control-Allow-Methods"]).to eq "POST, OPTIONS"
      expect(response.headers["Access-Control-Allow-Headers"]).to be_nil
      expect(response.headers["Access-Control-Allow-Credentials"]).to be_nil
    end
  end

  describe "POST /oauth/token" do
    before do
      post "/oauth/token", headers: { Origin: "https://wolf.dev" }
    end

    it_behaves_like "cross-origin POST request"
  end
end
