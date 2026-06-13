require "omniauth_openid_connect"

class OmniAuth::Strategies::Discord < OmniAuth::Strategies::OpenIDConnect
  option :name, "discord"

  option :issuer, "https://discord.com"
  option :discovery, true

  option :client_options, {
    identifier: nil,
    secret: nil,
    redirect_uri: nil,
    scheme: "https",
    host: "discord.com",
    port: 443
  }

  option :scope, %i[openid email]

  def redirect_uri
    return client_options.redirect_uri if client_options.redirect_uri

    full_host + script_name + callback_path
  end
end
