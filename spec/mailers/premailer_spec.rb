require "rails_helper"

RSpec.describe "Mailer CSS inlining" do
  let(:user) { FactoryBot.create(:user) }

  let(:delivered) do
    UserMailer.reset_password_instructions(user, "abc123").deliver_now
    ActionMailer::Base.deliveries.last
  end

  let(:html) { delivered.html_part.body.decoded }

  it "inlines layout styles onto elements" do
    body_div = Nokogiri::HTML(html).at_css("div.email-body")
    expect(body_div["style"]).to include("background-color: #fff")
  end

  it "keeps the dark mode media query" do
    expect(html).to include("prefers-color-scheme: dark")
  end

  it "keeps the hand-written text part" do
    expect(delivered.text_part.body.decoded).to include("reset_password_token=abc123")
    expect(delivered.text_part.body.decoded).not_to include("<")
  end

  it "marks every media query declaration !important so it beats the inlined styles" do
    css = Rails.application.assets.load_path.find("mailer.css").content
    parser = CssParser::Parser.new
    parser.add_block!(css)

    offenders = []
    parser.each_rule_set do |rule_set, media_types|
      next if media_types == [:all]

      rule_set.each_declaration do |property, _value, important|
        offenders << "#{rule_set.selectors.join(", ")} { #{property} }" unless important
      end
    end

    expect(offenders).to be_empty
  end
end
