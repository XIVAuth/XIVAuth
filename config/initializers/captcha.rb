RailsCloudflareTurnstile.configure do |c|
  turnstile_test_site_key = "3x00000000000000000000FF".freeze
  turnstile_test_secret_key = "1x0000000000000000000000000000000AA".freeze

  c.site_key = Rails.application.credentials.dig(:turnstile, :site_key) || turnstile_test_site_key
  c.secret_key = Rails.application.credentials.dig(:turnstile, :secret_key) || turnstile_test_secret_key
  c.size = "flexible"

  c.mock_enabled = false
  c.fail_open = Rails.env.development?
end
