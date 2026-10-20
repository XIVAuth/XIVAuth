class EmailDelivery::CloudflareDeliveryMethod < Cloudflare::EmailService::Rails::DeliveryMethod
  def deliver!(mail)
    response = super

    if response.permanent_bounces.any?
      raise EmailDelivery::RecipientRejected, "Permanent bounce for #{response.permanent_bounces.join(", ")}"
    end

    response
  end
end
