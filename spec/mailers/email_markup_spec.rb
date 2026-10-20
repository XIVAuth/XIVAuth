require "rails_helper"

RSpec.describe "Gmail email markup" do
  let(:token) { "abc123" }

  def delivered_markup(mail)
    mail.deliver_now
    html = ActionMailer::Base.deliveries.last.html_part.body.decoded
    scripts = Nokogiri::HTML(html).css('script[type="application/ld+json"]')
    expect(scripts.size).to eq(1)

    JSON.parse(scripts.first.text)
  end

  it "adds a one-click confirm action to the welcome email" do
    user = FactoryBot.create(:user, confirmed_at: nil)
    markup = delivered_markup(UserMailer.confirmation_instructions(user, token))

    action = markup["potentialAction"]
    expect(action["@type"]).to eq("ConfirmAction")
    expect(action.dig("handler", "url")).to eq("http://example.com/auth/register/confirm?confirmation_token=#{token}")
  end

  it "adds a one-click confirm action to the email change email" do
    user = FactoryBot.create(:user)
    allow(user).to receive(:pending_reconfirmation?).and_return(true)
    markup = delivered_markup(UserMailer.confirmation_instructions(user, token, to: "new@example.test"))

    expect(markup.dig("potentialAction", "@type")).to eq("ConfirmAction")
    expect(markup.dig("potentialAction", "name")).to eq("Confirm New Email")
  end

  it "adds a go-to action to the password reset email" do
    user = FactoryBot.create(:user)
    markup = delivered_markup(UserMailer.reset_password_instructions(user, token))

    expect(markup["potentialAction"]).to include(
      "@type" => "ViewAction",
      "url" => "http://example.com/auth/recovery/password?reset_password_token=#{token}"
    )
  end

  it "does not add markup to emails without actions" do
    registration = FactoryBot.create(:verified_registration)
    CharacterRegistrationMailer.with(registration: registration).character_verified_elsewhere.deliver_now

    expect(ActionMailer::Base.deliveries.last.html_part.body.decoded).not_to include("application/ld+json")
  end

  it "links verification emails to the current confirmation route" do
    user = FactoryBot.create(:user, confirmed_at: nil)
    mail = UserMailer.confirmation_instructions(user, token)

    [mail.html_part, mail.text_part].each do |part|
      body = part.body.decoded
      expect(body).to include("/auth/register/confirm?confirmation_token=#{token}")
      expect(body).not_to include("/users/confirmation")
      expect(body).not_to include(user.id)
    end
  end
end
