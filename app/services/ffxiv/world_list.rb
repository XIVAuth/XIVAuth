require "yaml"

class FFXIV::WorldList
  CACHE_KEY = "ffxiv:worlds".freeze
  CACHE_EXPIRY = 1.week
  EXCLUDE_REGIONS = [
    "NA_CLOUD"
  ].freeze

  XIVAPI_SCHEMA_VERSION = "exdschema@2:rev:75f674655bb89d6172effa3a5a2d93bcfc7deb51"

  class << self
    def all
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY, race_condition_ttl: 30.seconds) do
        fetch_from_api
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to fetch worlds from cache/API, attempting stale cache: #{e.message}")
      stale_data = Rails.cache.read(CACHE_KEY)

      if stale_data.present?
        stale_data
      else
        Rails.logger.error("No cached data available, using fallback")
        fallback_worlds
      end
    end

    # Force refresh the cache (called by cronjob)
    def refresh!
      Rails.cache.delete(CACHE_KEY)
      all
    end

    # Get just world names for select options
    def names
      all.pluck(:name).sort
    end

    # Group worlds by datacenter
    def by_datacenter
      all.group_by { |w| w[:datacenter] }
    end

    # Group worlds by region
    def by_region
      all.group_by { |w| w[:region] }
    end

    # Returns grouped options for Rails select helper: { "DC (Region)" => [["World", "World"], ...] }
    def grouped_options
      datacenters = by_datacenter
      result = datacenters.to_h do |datacenter, worlds|
        region = worlds.first[:region]
        key = "#{datacenter} (#{region})"
        value = worlds.map { |w| [w[:name], w[:name]] }.sort_by(&:first)
        [key, value]
      end

      result.sort_by(&:first)
    end

    # Fetch world data from XIVAPI and transform it
    # @return [Array<Hash>] Transformed world data
    private def fetch_from_api
      results = FFXIV::XIVAPISearchClient.search(
        sheet: "World",
        fields: %w[Name DataCenter.Name DataCenter.Region.Name],
        query: "IsPublic=true",
        schema: XIVAPI_SCHEMA_VERSION,
        language: "en"
      )

      # Use fallback if API returned nothing
      return fallback_worlds if results.empty?

      transform_worlds(results)
    end

    # Transform raw XIVAPI results into World hashes
    # @param results [Array<Hash>] Raw XIVAPI results
    # @return [Array<Hash>] Transformed world data
    private def transform_worlds(results)
      worlds = results.map do |world|
        fields = world["fields"] || { }
        datacenter_fields = fields.dig("DataCenter", "fields") || { }

        {
          name: fields["Name"],
          datacenter: datacenter_fields["Name"],
          region: normalize_region(datacenter_fields.dig("Region", "value"))
        }
      end

      # Filter out invalid entries and excluded regions, then sort by name
      worlds.select { |w| w[:name].present? && w[:datacenter].present? && EXCLUDE_REGIONS.exclude?(w[:region]) }
            .sort_by { |w| w[:name] }
    end

    # Normalize region codes (e.g., 1 => "JP", 2 => "NA", 3 => "EU")
    private def normalize_region(region_code)
      case region_code
      when 1, "1", "Japan" then "JP"
      when 2, "2", "North America" then "NA"
      when 3, "3", "Europe" then "EU"
      when 4, "4", "Oceania" then "OCE"
      when 7, "7", "NA Cloud" then "NA_CLOUD"
      else
        Rails.logger.warn("Unknown XIVAPI region code: #{region_code}")
        region_code.to_s
      end
    end

    # Load fallback world list from YAML file
    # YAML structure: Region -> Datacenter -> [World Names]
    # Returns: [{ name:, datacenter:, region: }, ...]
    private def fallback_worlds
      @fallback_worlds ||= begin
        fallback_path = Rails.root.join("config/ffxiv_data/fallback_worlds.yml")
        nested_data = YAML.safe_load_file(fallback_path)

        # Flatten the nested structure into the format used by the cache
        worlds = []
        nested_data.each do |region, datacenters|
          datacenters.each do |datacenter, world_names|
            world_names.each do |world_name|
              worlds << { name: world_name, datacenter: datacenter, region: region }
            end
          end
        end

        worlds.sort_by { |w| w[:name] }
      rescue StandardError => e
        Rails.logger.error("Failed to load fallback worlds: #{e.message}")
        []
      end
    end
  end
end
