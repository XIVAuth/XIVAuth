module Flarestone
  class CachedProfile
    CACHE_TTL = 24.hours
    CACHE_KEY_PREFIX = "flarestone:character"

    def self.fetch(lodestone_id, force_fresh: false)
      new(lodestone_id).fetch(force_fresh: force_fresh)
    end

    attr_reader :fresh

    alias fresh? fresh

    def initialize(lodestone_id)
      @lodestone_id = lodestone_id
      @fresh = false
    end

    # Returns raw Flarestone JSON for the character, reading from cache unless force_fresh is true.
    # Always writes fresh data back to the cache when fetching from Flarestone.
    # Check fresh? after calling to determine whether Flarestone was hit.
    def fetch(force_fresh: false)
      unless force_fresh
        cached = Rails.cache.read(cache_key)
        return cached if cached.present?
      end

      response = connection.get("#{base_url}/character/#{@lodestone_id}")
      json = JSON.parse(response.body)

      Rails.logger.debug("Fetched character from Flarestone.", lodestone_id: @lodestone_id,
                         status: response.status, meta: json["_meta"])

      Rails.cache.write(cache_key, json, expires_in: CACHE_TTL)
      @fetched_fresh = true
      json
    end

    private def cache_key
      "#{CACHE_KEY_PREFIX}:#{@lodestone_id}"
    end

    private def base_url
      Rails.application.credentials.dig(:flarestone, :host) || "https://flarestone.xivauth.net"
    end

    private def connection
      Faraday.new(headers: { "X-API-Key": Rails.application.credentials.dig(:flarestone, :api_key) })
    end
  end
end
