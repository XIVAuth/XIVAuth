class Users::ApiAvatarResolver
  def initialize(access_token)
    @access_token = access_token
  end

  def resolve
    return nil unless user

    return Rails.application.routes.url_helpers.url_for(user.avatar) if user.avatar.present?

    candidate_avatar_urls = authorized_registrations.joins(:character).limit(2)
                                                    .pluck("ffxiv_characters.avatar_url")

    # special case: if we're only allowed to see one character, we can assume that it would
    # make a good avatar.
    return candidate_avatar_urls.first if candidate_avatar_urls.size == 1

    # only return a gravatar url if the user is sharing their email.
    # gravatar keys on email hash, so we don't want to leak data.
    return user.gravatar_url(256) if scope_granted?("user:email")

    # otherwise, try to find the default character visible to this client.
    # Or: .first will return null if the array is empty and the client can decide what to do.
    candidate_avatar_urls.first
  end

  private def user
    return nil if @access_token.blank?
    return nil unless @access_token.resource_owner_type == "User"

    @user ||= User.find_by(id: @access_token.resource_owner_id)
  end

  private def authorized_registrations
    return CharacterRegistration.none unless character_scope_granted?

    registrations = user.character_registrations.verified
    return registrations if scope_granted?("character:manage")

    policy = @access_token.permissible_policy
    return registrations if policy.blank?

    policy.filter_accessible(registrations)
  end

  private def character_scope_granted?
    scope_granted?("character") || scope_granted?("character:all") ||
      scope_granted?("character:manage") || scope_granted?("character:jwt")
  end

  private def scope_granted?(scope)
    @access_token.scopes.exists?(scope)
  end
end
