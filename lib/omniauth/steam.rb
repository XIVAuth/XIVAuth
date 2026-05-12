require "active_support/security_utils"
require "faraday"
require "json"
require "omniauth"
require "securerandom"
require "uri"

module OmniAuth
  module Strategies
    class Steam
      include OmniAuth::Strategy

      OPENID_ENDPOINT = "https://steamcommunity.com/openid/login"
      OPENID_NS       = "http://specs.openid.net/auth/2.0"
      STEAM_ID_RE     = %r{\Ahttps://steamcommunity\.com/openid/id/(\d{17})\z}
      STATE_SESSION_KEY = "omniauth.steam.state".freeze

      args [:api_key]
      option :name, "steam"
      option :api_key, nil

      uid { steam_id }

      info do
        {
          nickname: player["personaname"],
          name:     player["realname"].presence,
          image:    player["avatarmedium"],
          urls:     { "Profile" => player["profileurl"] }.compact
        }
      end

      extra { { raw_info: player } }

      def request_phase
        state = SecureRandom.hex(32)
        session[STATE_SESSION_KEY] = state
        redirect "#{OPENID_ENDPOINT}?#{URI.encode_www_form(openid_request_params(state))}"
      end

      def callback_phase
        return fail!(:csrf_detected) unless valid_state?
        return fail!(:invalid_credentials) unless valid_openid_response?
        return fail!(:invalid_credentials) unless steam_confirmed?
        return fail!(:invalid_credentials) unless steam_id
        super
      end

      def callback_url
        full_host + script_name + callback_path
      end

      private

      def openid_request_params(state)
        {
          "openid.ns"         => OPENID_NS,
          "openid.mode"       => "checkid_setup",
          "openid.identity"   => "#{OPENID_NS}/identifier_select",
          "openid.claimed_id" => "#{OPENID_NS}/identifier_select",
          "openid.return_to"  => "#{callback_url}?#{URI.encode_www_form(state: state)}",
          "openid.realm"      => "#{request.scheme}://#{request.host_with_port}/"
        }
      end

      def valid_state?
        expected = session.delete(STATE_SESSION_KEY)
        provided = request.params["state"]
        expected && provided.is_a?(String) &&
          ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      end

      def valid_openid_response?
        request.params["openid.mode"] == "id_res" &&
          request.params["openid.ns"] == OPENID_NS &&
          request.params["openid.return_to"]&.start_with?(callback_url)
      end

      def steam_confirmed?
        verify_params = request.params
          .select { |k, _| k.start_with?("openid.") }
          .merge("openid.mode" => "check_authentication")

        response = http.post(OPENID_ENDPOINT, verify_params)
        return false unless response.success?

        response.body.include?("is_valid:true")
      end

      def steam_id
        @steam_id ||= STEAM_ID_RE.match(request.params["openid.claimed_id"])&.[](1)
      end

      def player
        @player ||= fetch_player || {}
      end

      def fetch_player
        return unless options.api_key && steam_id

        response = http.get(
          "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/",
          key: options.api_key, steamids: steam_id
        )
        return unless response.success?

        JSON.parse(response.body).dig("response", "players", 0)
      rescue JSON::ParserError
        nil
      end

      def http
        @http ||= Faraday.new(request: { open_timeout: 3, timeout: 5 })
      end
    end
  end
end
