class Users::ApiAvatarResolver
  def initialize(access_token)
    @access_token = access_token
  end

  def resolve
    return nil unless user

    return Rails.application.routes.url_helpers.url_for(user.avatar) if user.avatar.present?

    # only return a gravatar url if the user is sharing their email.
    # gravatar keys on email hash, so we don't want to leak data.
    return user.gravatar_url(256) if scope_granted?("user:email")

    # no avatar - let the consuming application decide what to do.
    nil
  end

  private def user
    return nil if @access_token.blank?
    return nil unless @access_token.resource_owner_type == "User"

    @user ||= User.find_by(id: @access_token.resource_owner_id)
  end

  private def character_scope_granted?
    scope_granted?("character") || scope_granted?("character:all") ||
      scope_granted?("character:manage") || scope_granted?("character:jwt")
  end

  private def scope_granted?(scope)
    @access_token.scopes.exists?(scope)
  end
end
