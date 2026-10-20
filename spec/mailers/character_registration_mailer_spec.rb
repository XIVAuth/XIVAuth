require "rails_helper"

RSpec.describe CharacterRegistrationMailer do
  describe "#character_verified_elsewhere" do
    let(:registration) { FactoryBot.create(:verified_registration) }
    let(:mail) { described_class.with(registration: registration).character_verified_elsewhere }

    it "is addressed to the user" do
      expect(mail.to).to eq([registration.user.email])
      expect(mail.subject).to include(registration.character.name)
    end

    it "renders both HTML and text parts without leftover placeholders" do
      [mail.html_part, mail.text_part].each do |part|
        body = part.body.decoded
        expect(body).not_to include("{{")
        expect(body).to include(registration.character.name)
      end
      expect(mail.html_part.body.decoded).to include(registration.character.lodestone_url)
      expect(mail.text_part.body.decoded).to include("http://example.com/discord")
      expect(mail.text_part.body.decoded).to include("http://example.com/characters")
    end
  end
end
