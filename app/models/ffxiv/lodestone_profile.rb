class FFXIV::LodestoneProfile
  include ActiveModel::API

  class LodestoneProfileInvalid < StandardError; end
  class LodestoneCharacterHidden < LodestoneProfileInvalid; end
  class LodestoneProfilePrivate < LodestoneProfileInvalid; end
  class LodestoneMaintenance < LodestoneProfileInvalid; end

  FREE_TRIAL_LEVEL_CAP = 70
  FAILURE_REASONS = %i[unspecified hidden_character profile_private not_found lodestone_maintenance].freeze

  attr_accessor :id, :last_parsed, :raw_data, :failure_reason

  validate :validate_lodestone_response

  # Create a LodestoneProfile for the given character ID.
  # Fetches via Flarestone::CachedProfile unless json_object is injected (e.g. in tests).
  #
  # @param lodestone_id [Integer,String]
  # @param json_object [Hash, nil] inject raw JSON to skip network I/O
  # @param force_fresh [Boolean] bypass cache and fetch directly from Flarestone
  def initialize(lodestone_id, json_object: nil, force_fresh: false)
    super()

    json_object ||= Flarestone::CachedProfile.fetch(lodestone_id, force_fresh: force_fresh)

    self.raw_data = json_object
    self.id = lodestone_id
    self.last_parsed = Time.now
  end

  # The name of this character.
  def name
    self.raw_data["name"]
  end

  def title
    self.raw_data["title"]
  end

  def world
    self.raw_data["world"]
  end

  def datacenter
    self.raw_data["datacenter"]
  end

  # The URL of this character's avatar ("headshot") image.
  def avatar
    self.raw_data["headshotUrl"]
  end

  # The URL of this character's portrait (full body) image.
  def portrait
    self.raw_data["portraitUrl"] || avatar.sub("fc0.jpg", "fl0.jpg")
  end

  def bio
    self.raw_data["bio"]
  end

  def free_company
    fc_data = self.raw_data["freeCompany"]
    return nil if fc_data.nil?

    {
      name: fc_data["name"],
      id: fc_data["lodestoneUrl"].match(/\/(\d+)\//)[1].to_i
    }
  end

  def class_levels
    self.raw_data["levels"].deep_symbolize_keys
  end

  # Check if this character is known to be paid. Returns true heuristically.
  # A false value does not indicate that this is a free trial character.
  def paid_character?
    free_company&.present? || class_levels.values.any? { |x| x > FREE_TRIAL_LEVEL_CAP }
  end

  # Visibility and existence checks (also validations)

  def validate_lodestone_response
    result_code = self.raw_data.dig("_meta", "resultCode")

    case result_code
    when "success"
      self.failure_reason = nil
    when "profile_private"
      self.failure_reason = :profile_private
      # note: this is still valid, we just don't have all the data.
    when "not_found"
      self.failure_reason = :not_found
      errors.add(:base, :not_found, message: "could not be found.")
    when "character_hidden"
      self.failure_reason = :hidden_character
      errors.add(:base, :hidden_character, message: "is marked as hidden or private.")
    when "maintenance"
      self.failure_reason = :lodestone_maintenance
      errors.add(:base, :maintenance, message: "can not be fetched due to maintenance. Please try again later.")
    else
      self.failure_reason = :unspecified
      errors.add(:base, :unspecified, message: "could not be fetched at this time. Please try again later.")
    end
  end
end
