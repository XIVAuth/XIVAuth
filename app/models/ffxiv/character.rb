class FFXIV::Character < ApplicationRecord
  self.implicit_order_column = "lodestone_id"
  validates :lodestone_id, presence: true, uniqueness: true
  
  # We don't care about failures on updates, as the existing data is still "valid"
  # In the update case (the only other time @lodestone_data is set), we already have valid data
  # and handle the failure accordingly.
  validate :lodestone_data_ok?, on: :create

  validates :name, presence: true
  validates :home_world, presence: true
  validates :data_center, presence: true

  validates :refresh_fail_reason,
            inclusion: FFXIV::LodestoneProfile::FAILURE_REASONS,
            allow_nil: true

  has_many :character_registrations, dependent: :destroy
  has_one :ban, as: :character, class_name: "CharacterBan", dependent: :destroy

  after_save :call_character_saves

  def lodestone_url(region = nil)
    region ||= "na"
    "https://#{region}.finalfantasyxiv.com/lodestone/character/#{lodestone_id}"
  end

  def home_with_datacenter
    "#{home_world} [#{data_center}]"
  end

  def stale?(hours = 24, failed_refresh_timeout_mins = 15)
    updated_at <= hours.hours.ago || (refresh_fail_reason.present? && updated_at <= failed_refresh_timeout_mins.minutes.ago)
  end

  def verified?
    if character_registrations.loaded?
      character_registrations.any?(&:verified?)
    else
      character_registrations.verified.exists?
    end
  end

  def verified_owner
    if character_registrations.loaded?
      character_registrations.select(&:verified?).first&.user
    else
      character_registrations.verified.first&.user
    end
  end

  def refresh_fail_reason
    super&.downcase&.to_sym || nil
  end

  def refresh_fail_reason=(reason)
    super(reason&.to_s&.upcase || nil)
  end

  def refresh_from_lodestone(lodestone_data = nil)
    return if lodestone_id.nil? && lodestone_data.nil?

    @lodestone_data = lodestone_data || FFXIV::LodestoneProfile.new(lodestone_id, force_fresh: true)
    unless @lodestone_data.valid?
      self.refresh_fail_reason = @lodestone_data.failure_reason
      return
    end

    # If we're at this point, the data is "valid" even if the profile is private. We can update what we got at the very
    # least.
    self.name = @lodestone_data.name
    self.home_world = @lodestone_data.world
    self.data_center = @lodestone_data.datacenter
    self.avatar_url = @lodestone_data.avatar
    self.portrait_url = @lodestone_data.portrait

    # clear or otherwise handle non-"critical" cases
    self.refresh_fail_reason = @lodestone_data.failure_reason
    self.updated_at = @lodestone_data.last_parsed if @lodestone_data.last_parsed.present?
  end

  def self.for_lodestone_id(lodestone_id)
    return nil if lodestone_id.nil?

    existing = find_by(lodestone_id: lodestone_id)
    return existing if existing.present?

    character = new(lodestone_id: lodestone_id)
    character.refresh_from_lodestone

    character
  end

  private def lodestone_data_ok?
    errors.merge!(@lodestone_data.errors) if @lodestone_data.present? && !@lodestone_data.valid?
  end

  private def call_character_saves
    character_registrations.in_batches.each_record do |record|
      record.run_callbacks(:save)
    end
  end
end
