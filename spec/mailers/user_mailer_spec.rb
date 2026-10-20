require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { FactoryBot.create(:user) }
  let(:token) { "abc123" }

  shared_examples "a multipart email" do |*expected_strings|
    it "renders both HTML and text parts without leftover placeholders" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present

      [mail.html_part, mail.text_part].each do |part|
        body = part.body.decoded
        expect(body).not_to include("{{")
        expected_strings.each { |s| expect(body).to include(s) }
      end
    end
  end

  describe "#reset_password_instructions" do
    let(:mail) { described_class.reset_password_instructions(user, token) }

    it "is addressed to the user" do
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq(I18n.t("devise.mailer.reset_password_instructions.subject"))
    end

    it_behaves_like "a multipart email", "reset_password_token=abc123", "6 hours"

    it "links to the recovery form in the text part" do
      expect(mail.text_part.body.decoded).to include("http://example.com/auth/recovery")
    end
  end

  describe "#confirmation_instructions" do
    context "with a new account" do
      let(:user) { FactoryBot.create(:user, confirmed_at: nil) }
      let(:mail) { described_class.confirmation_instructions(user, token) }

      it "is addressed to the user" do
        expect(mail.to).to eq([user.email])
        expect(mail.subject).to eq(I18n.t("devise.mailer.confirmation_instructions.subject"))
      end

      it_behaves_like "a multipart email", "confirmation_token=abc123"
    end

    context "with a pending email change" do
      let(:new_email) { "o'brien@example.test" }
      let(:mail) { described_class.confirmation_instructions(user, token, to: new_email) }

      before do
        allow(user).to receive(:pending_reconfirmation?).and_return(true)
      end

      it "is addressed to the new email address" do
        expect(mail.to).to eq([new_email])
        expect(mail.subject).to eq(I18n.t("devise.mailer.reconfirmation_instructions.subject"))
      end

      it_behaves_like "a multipart email", "confirmation_token=abc123"

      it "does not HTML-escape the text part" do
        expect(mail.text_part.body.decoded).to include(new_email)
      end
    end
  end
end
