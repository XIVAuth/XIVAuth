require "rails_helper"

RSpec.describe "cloudflare_mta flag" do
  let(:client) { instance_double(Cloudflare::EmailService::Client) }
  let(:user) { FactoryBot.create(:user) }
  let(:other_user) { FactoryBot.create(:user) }

  let(:cloudflare_response) do
    Cloudflare::EmailService::Response.new(status: 200, body: { "success" => true, "result" => { "delivered" => [] } })
  end

  before do
    ApplicationMailer.cloudflare_settings = { client: client }
    allow(client).to receive(:deliver).and_return(cloudflare_response)
  end

  after do
    ApplicationMailer.cloudflare_settings = ActionMailer::Base.cloudflare_settings
  end

  def send_reset_to(recipient)
    UserMailer.reset_password_instructions(recipient, "abc123").deliver_now
  end

  it "delivers through the environment's default method when the flag is off" do
    expect { send_reset_to(user) }.to change(ActionMailer::Base.deliveries, :count).by(1)
    expect(client).not_to have_received(:deliver)
  end

  it "delivers through Cloudflare when the flag is enabled globally" do
    Flipper.enable(:cloudflare_mta)

    expect { send_reset_to(user) }.not_to change(ActionMailer::Base.deliveries, :count)
    expect(client).to have_received(:deliver).once
  end

  context "when the flag is enabled for one user" do
    before { Flipper.enable_actor(:cloudflare_mta, user) }

    it "routes that user's Devise emails through Cloudflare" do
      send_reset_to(user)

      expect(client).to have_received(:deliver) { |message| expect(message.to).to eq([user.email]) }
    end

    it "leaves other users on the default method" do
      expect { send_reset_to(other_user) }.to change(ActionMailer::Base.deliveries, :count).by(1)
      expect(client).not_to have_received(:deliver)
    end

    it "routes that user's character alerts through Cloudflare" do
      registration = FactoryBot.create(:verified_registration, user: user)

      CharacterRegistrationMailer.with(registration: registration).character_verified_elsewhere.deliver_now

      expect(client).to have_received(:deliver).once
    end
  end

  it "still translates Cloudflare errors when routed by the flag" do
    Flipper.enable(:cloudflare_mta)
    allow(client).to receive(:deliver).and_raise(Cloudflare::EmailService::ServerError.new("boom", status: 503))

    expect { send_reset_to(user) }.to raise_error(EmailDelivery::Failed)
  end
end
