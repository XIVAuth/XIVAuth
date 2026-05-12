require "json"
require "faraday"

# Search client using Flarestone to find characters by name and world/datacenter.
class FFXIV::LodestoneSearch
  attr_reader :name, :world, :datacenter, :error, :error_status

  def initialize(name:, world: nil, datacenter: nil, exact: false)
    @name = name
    @world = world
    @datacenter = datacenter
    @exact = exact
    @error = nil
    @error_status = nil
  end

  class << self
    def connection
      @connection ||= Faraday.new(
        headers: {
          "X-API-Key": Rails.application.credentials.dig(:flarestone, :api_key)
        },
        request: {
          timeout: 10,       # Total request timeout in seconds
          open_timeout: 2    # Connection timeout in seconds
        }
      )
    end
  end

  def results
    json = fetch_results
    return [] unless json.is_a?(Hash)

    items = json.fetch("results", [])
    items.map do |item|
      {
        lodestone_id: item["id"].to_i,
        name: item["name"],
        world: item["world"],
        datacenter: item["datacenter"],
        avatar_url: item["avatarUrl"]
      }
    end
  end

  def error?
    error.present? || error_status.present?
  end

  private def fetch_results
    flarestone_base_url = Rails.application.credentials.dig(:flarestone, :host) || "https://flarestone.xivauth.net"

    params = { name: name }
    params[:world] = world if world.present?
    params[:datacenter] = datacenter if datacenter.present?
    params[:exact] = true if @exact

    response = self.class.connection.get("#{flarestone_base_url}/character/search", params)

    if response.status != 200
      @error_status = response.status
      case response.status
      when 401
        @error = "Character search service is not configured. Please contact support."
        Rails.logger.error("Flarestone API returned 401 - API key is missing or invalid")
      when 429
        @error = "Rate limited. Please try again in a moment."
      when 503
        @error = "Lodestone service is currently unavailable. Please try again later."
      when 500..599
        @error = "Service error. Please try again later."
      else
        @error = "An error occurred while searching. Please try again."
      end
      return { }
    end

    JSON.parse(response.body)
  rescue Faraday::Error
    @error = "Network error. Unable to reach the character search service."
    @error_status = "network"
    { }
  rescue JSON::ParserError
    @error = "Invalid response from character search service. Please try again."
    @error_status = "parse_error"
    { }
  end
end
