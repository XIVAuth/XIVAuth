module CharacterRegistrationsHelper
  # A more relaxed regex variant to extract metadata from a Lodestone URI.
  LODESTONE_URL_REGEX =
    %r{(?:(?:https?://)?(?<region>[a-z]{2})\.finalfantasyxiv\.com/lodestone/character/)?(?<lodestone_id>\d+)(?:/.*)?}

  def extract_data(id_or_url)
    if (res = LODESTONE_URL_REGEX.match(id_or_url))
      return res.named_captures.deep_symbolize_keys
    end

    return { }
  end

  def can_add_characters?
    current_user.character_registrations.unverified.count < current_user.unverified_character_allowance
  end

  def world_options
    FFXIV::WorldList.grouped_options
  end
end
