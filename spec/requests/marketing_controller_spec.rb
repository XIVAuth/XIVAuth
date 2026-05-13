require "rails_helper"

RSpec.describe "MarketingController" do
  describe "GET / (index)" do
    it "raises UnknownFormat for unsupported Accept formats" do
      expect {
        get root_path, headers: { "Accept" => "text/plain" }
      }.to raise_error(ActionController::UnknownFormat)
    end
  end
end