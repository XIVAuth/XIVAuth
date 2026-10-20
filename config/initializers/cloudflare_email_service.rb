Cloudflare::EmailService.configure do |c|
  c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
  c.api_token = Rails.application.credentials.dig(:cloudflare, :mailer, :api_key)
end

Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :cloudflare, EmailDelivery::CloudflareDeliveryMethod
end
