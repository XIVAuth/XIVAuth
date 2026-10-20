class ApplicationMailer < ActionMailer::Base
  default from: "XIVAuth <noreply@xivauth.net>"
  layout "mailer"

  after_action :route_to_cloudflare, if: -> { Flipper.enabled?(:cloudflare_mta, mta_actor) }

  rescue_from "Postmark::Error", "Cloudflare::EmailService::APIError", "Cloudflare::EmailService::NetworkError" do |e|
    raise EmailDelivery::Failed, e.message
  end

  rescue_from "Postmark::InactiveRecipientError" do |e|
    raise EmailDelivery::RecipientRejected, e.message
  end

  rescue_from "Postmark::InvalidEmailRequestError" do |e|
    raise EmailDelivery::InvalidRecipient, e.message
  end

  # The Flipper actor for :cloudflare_mta, normally the recipient. Without one, only the boolean and
  # percentage-of-time gates apply.
  private def mta_actor = nil

  private def route_to_cloudflare
    wrap_delivery_behavior!(:cloudflare)
  end
end
