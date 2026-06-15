module Api::FiltersAuthorizedCharacters
  extend ActiveSupport::Concern

  # Load character registrations that are authorized for the current OAuth token,
  # considering both CanCan abilities and permissible policies.
  #
  # @return [ActiveRecord::Relation<CharacterRegistration>] Authorized character registrations
  def authorized_character_registrations(only_verified: false)
    # Return empty set if no character scope is present
    return CharacterRegistration.none unless character_scope_granted?

    registrations = CharacterRegistration.accessible_by(current_ability)

    # If the token has character:manage scope, grant full access to all user's characters
    # Note: check only_verified here to avoid double-filtering after the chain.
    if character_manage_scope_granted?
      return registrations.verified if only_verified
      return registrations
    end

    # Otherwise, filter to verified characters only
    registrations = registrations.verified

    # Apply permissible policy restrictions if present
    policy = doorkeeper_token.permissible_policy
    if policy.present?
      registrations = policy.filter_accessible(registrations)
    elsif !bulk_character_scope_granted?
      # Default-deny `character` scope if there's no policy (somehow)
      # Note: character:all without a policy does request *all* characters, so this is just pure character.
      return CharacterRegistration.none
    end

    registrations
  end

  # Check if the current OAuth token has the character:manage scope
  #
  # @return [Boolean] true if character:manage scope is present
  def character_manage_scope_granted?
    doorkeeper_token.scopes.include?("character:manage")
  end

  # Check if the current OAuth token has any character scope
  #
  # @return [Boolean] true if any character scope is present
  def character_scope_granted?
    doorkeeper_token.scopes.exists?("character") ||
      doorkeeper_token.scopes.exists?("character:all") ||
      doorkeeper_token.scopes.exists?("character:manage") ||
      doorkeeper_token.scopes.exists?("character:jwt")
  end

  def bulk_character_scope_granted?
    doorkeeper_token.scopes.exists?("character:all") ||
      doorkeeper_token.scopes.exists?("character:manage")
  end
end
