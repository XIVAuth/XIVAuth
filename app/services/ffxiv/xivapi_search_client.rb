require "json"
require "faraday"

# Lightweight client for XIVAPI v2 search queries
class FFXIV::XIVAPISearchClient
  BASE_URL = "https://v2.xivapi.com/api/search".freeze

  # Executes an XIVAPI search query
  #
  # @param sheet [String] The XIVAPI sheet name (e.g., "World")
  # @param fields [Array<String>] Field names to retrieve (e.g., ["Name", "DataCenter.Name"])
  # @param query [String, nil] Optional query filter (e.g., "IsPublic=true")
  # @return [Array<Hash>] Array of result hashes from XIVAPI
  # @raise [StandardError] If the API request fails
  def self.search(sheet:, fields:, schema:, language:, query: nil)
    params = {
      sheets: sheet,
      fields: fields.join(","),
      schema: schema,
      language: language,
      query: query
    }
    params.compact!

    conn = Faraday.new do |f|
      f.options.timeout = 5 # Total request timeout in seconds
      f.options.open_timeout = 2 # Connection timeout in seconds
    end

    response = conn.get(BASE_URL, params)

    unless response.status == 200
      error_msg = "XIVAPI returned #{response.status}"
      error_msg += ": #{response.body[0..500]}" if response.body.present?
      raise error_msg
    end

    data = JSON.parse(response.body)
    data.fetch("results", [])
  rescue Faraday::Error => e
    Rails.logger.error("Faraday error fetching from XIVAPI: #{e.message}")
    raise
  rescue JSON::ParserError => e
    Rails.logger.error("JSON parse error from XIVAPI: #{e.message}")
    raise
  end
end
