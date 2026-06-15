require "omniauth-oauth2"

# Based off of https://github.com/adaoraul/omniauth-discord, updated with Pomelo support.

class OmniAuth::Strategies::Discord < OmniAuth::Strategies::OAuth2
  DEFAULT_SCOPE = "identify".freeze

  option :name, "discord"

  option :client_options,
         site: "https://discord.com/api",
         authorize_url: "oauth2/authorize",
         token_url: "oauth2/token"

  option :authorize_options, %i[scope permissions prompt]

  uid { raw_info["id"] }

  info do
    {
      name: raw_info["global_name"],
      nickname: username,
      email: raw_info["verified"] ? raw_info["email"] : nil,
      image: raw_info["avatar"] ? "https://cdn.discordapp.com/avatars/#{raw_info['id']}/#{raw_info['avatar']}" : nil
    }
  end

  extra do
    {
      raw_info:
    }
  end

  def raw_info
    @raw_info ||= access_token.get("users/@me").parsed
  end

  def username
    username = raw_info["username"]

    discriminator = raw_info["discriminator"]
    username += "##{discriminator}" if discriminator.present? && discriminator != "0"

    username
  end

  def callback_url
    # Discord does not support query parameters
    options[:redirect_uri] || (full_host + script_name + callback_path)
  end

  def authorize_params
    super.tap do |params|
      options[:authorize_options].each do |option|
        params[option] = request.params[option.to_s] if request.params[option.to_s]
      end

      params[:scope] ||= DEFAULT_SCOPE
    end
  end
end
