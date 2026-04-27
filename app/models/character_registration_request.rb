class CharacterRegistrationRequest
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :lodestone_url, :string
  attribute :search_name, :string
  attribute :search_world, :string
  attribute :user
  attribute :search_exact, :boolean, default: false

  attr_reader :candidates
  attr_accessor :character_search # NOTE: fake attribute for search feedback.
  attr_accessor :from_search

  attr_reader :created_registration
  delegate :character, to: :created_registration, allow_nil: true


  # Provide either a valid Lodestone URL/ID, or both name and world.
  validates :lodestone_url,
            format: { with: CharacterRegistrationsHelper::LODESTONE_URL_REGEX },
            allow_blank: true

  def ref_present?
    lodestone_url.to_s.strip.present?
  end

  def name_world_present?
    search_name.to_s.strip.present? && search_world.to_s.strip.present?
  end

  # Orchestrates the registration flow, attaching errors to field-level inputs when needed.
  # Returns :success, :confirm, :invalid (bad user input), or :failed (system/external failure).
  def process!
    if ref_present?
      process_ref_path
    elsif name_world_present?
      perform_search
    else
      errors.add(:base, :missing_inputs,
                 message: "Please provide either a Lodestone URL or both character name and world.")

      :invalid
    end
  end

  private

  def process_ref_path
    lodestone_data = CharacterRegistrationsHelper::LODESTONE_URL_REGEX.match(lodestone_url)&.named_captures&.symbolize_keys || {}
    lodestone_id_value = lodestone_data[:lodestone_id]

    unless lodestone_id_value.present?
      errors.add(:lodestone_url, "is not a valid Lodestone ID or URL")
      return :invalid
    end

    create_registration(lodestone_id_value, region: lodestone_data[:region], field_for_character_error: :lodestone_url)
  end

  def perform_search
    search = FFXIV::LodestoneSearch.new(name: search_name, world: search_world, exact: search_exact)
    @candidates = search.results

    if search.error?
      errors.add(:character_search, search.error)

      :failed
    elsif @candidates.empty?
      errors.add(:character_search, :no_results,
                 message: "could not find '#{search_name.titleize}' on '#{search_world}'.")

      :invalid
    elsif @candidates.length > 10
      errors.add(:character_search, :too_many_results,
                 message: "matched too many characters. Please refine your search.")

      :invalid
    elsif @candidates.length == 1
      register_single_candidate(@candidates.first[:lodestone_id])
    else
      :confirm
    end
  end

  def register_single_candidate(lodestone_id)
    create_registration(lodestone_id, field_for_character_error: :search_name)
  end

  # Consolidated method to create a CharacterRegistration
  # @param lodestone_id [String, Integer] The Lodestone character ID
  # @param region [String, nil] Optional region (na/eu/jp) extracted from URL
  # @param field_for_character_error [Symbol] Which field to attach character validation errors to
  # @return [Symbol] :success, :invalid, or :failed
  def create_registration(lodestone_id, region: nil, field_for_character_error: :search_name)
    extra_data = region.present? ? { region: region } : {}
    @created_registration = CharacterRegistration.build_from_lodestone(
      user: user,
      lodestone_id: lodestone_id,
      extra_data: extra_data
    )

    if @created_registration.save
      :success
    else
      attach_registration_errors(@created_registration, field_for_character_error: field_for_character_error)
      errors.any? { |e| %i[character base].include?(e.attribute) } ? :failed : :invalid
    end
  end

  # Routes CharacterRegistration errors to the appropriate semantic attribute on this object.
  # - :character errors (all from FFXIV::Character via validate_linked_character):
  #     :not_found → input field (user's input caused it)
  #     all others → :character (problem is with the character itself, not the input)
  # - All other CR-native errors (:base, :character_id, :user) → :base
  def attach_registration_errors(registration, field_for_character_error: :search_name)
    registration.errors.each do |error|
      case error.attribute
      when :character
        if error.type == :not_found
          errors.add(field_for_character_error, error.type, message: error.message)
        else
          errors.add(:character, error.type, message: error.message)
        end
      else
        errors.add(:base, error.type, message: error.full_message)
      end
    end
  end
end
