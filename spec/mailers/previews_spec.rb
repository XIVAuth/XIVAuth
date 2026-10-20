require "rails_helper"

Dir[Rails.root.join("spec/mailers/previews/**/*_preview.rb")].each { |f| require f }

RSpec.describe "Mailer previews" do
  ActionMailer::Preview.all.each do |preview|
    preview.emails.each do |email|
      it "renders #{preview.preview_name}/#{email}" do
        message = preview.call(email)

        expect(message.html_part.body.decoded).not_to include("{{")
        expect(message.text_part.body.decoded).not_to include("{{")
      end
    end
  end
end
