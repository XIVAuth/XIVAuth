require "rails_helper"

RSpec.describe "Email delivery error translation" do
  let(:user) { FactoryBot.create(:user) }
  let(:deliver) { -> { UserMailer.reset_password_instructions(user, "abc123").deliver_now } }

  context "with Postmark" do
    {
      "an inactive recipient" => [-> { Postmark::ApiInputError.build("inactive", { "ErrorCode" => 406 }) },
                                  EmailDelivery::RecipientRejected],
      "an invalid email" => [-> { Postmark::ApiInputError.build("invalid", { "ErrorCode" => 300 }) },
                             EmailDelivery::InvalidRecipient],
      "a timeout" => [-> { Postmark::TimeoutError.new("timed out") }, EmailDelivery::Failed]
    }.each do |description, (error, expected)|
      it "translates #{description} into #{expected}" do
        original = error.call
        allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(original)

        expect(&deliver).to raise_error(expected) { |e| expect(e.cause).to eq(original) }
      end
    end
  end

  context "with Cloudflare" do
    let(:client) { instance_double(Cloudflare::EmailService::Client) }

    before do
      UserMailer.delivery_method = :cloudflare
      UserMailer.cloudflare_settings = { client: client }
    end

    after do
      UserMailer.delivery_method = ActionMailer::Base.delivery_method
      UserMailer.cloudflare_settings = ActionMailer::Base.cloudflare_settings
    end

    def cloudflare_response(delivered: [], permanent_bounces: [], queued: [])
      Cloudflare::EmailService::Response.new(
        status: 200,
        body: { "success" => true,
                "result" => { "delivered" => delivered, "permanent_bounces" => permanent_bounces, "queued" => queued } }
      )
    end

    it "registers the bounce-checking delivery method as :cloudflare" do
      expect(ActionMailer::Base.delivery_methods[:cloudflare]).to eq(EmailDelivery::CloudflareDeliveryMethod)
    end

    it "sends the inlined HTML and text parts" do
      allow(client).to receive(:deliver) do |message|
        expect(message.html).to include('style="')
        expect(message.text).to include("reset_password_token=abc123")
        cloudflare_response(delivered: [user.email])
      end

      expect(&deliver).not_to raise_error
    end

    it "raises RecipientRejected when the recipient permanently bounces" do
      allow(client).to receive(:deliver).and_return(cloudflare_response(permanent_bounces: [user.email]))

      expect(&deliver).to raise_error(EmailDelivery::RecipientRejected, /#{Regexp.escape(user.email)}/)
    end

    it "does not raise for queued recipients" do
      allow(client).to receive(:deliver).and_return(cloudflare_response(queued: [user.email]))

      expect(&deliver).not_to raise_error
    end

    {
      "a rejected request" => Cloudflare::EmailService::RequestError.new("[10001] invalid", status: 400),
      "a rate limit" => Cloudflare::EmailService::RateLimitError.new("throttled", status: 429),
      "a network failure" => Cloudflare::EmailService::NetworkError.new("connection reset")
    }.each do |description, original|
      it "translates #{description} into EmailDelivery::Failed" do
        allow(client).to receive(:deliver).and_raise(original)

        expect(&deliver).to raise_error(EmailDelivery::Failed) { |e| expect(e.cause).to eq(original) }
      end
    end
  end
end
