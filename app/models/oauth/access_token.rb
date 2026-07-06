class OAuth::AccessToken < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken
  include OAuth::ScopesAsArray

  scope :active, -> { where(revoked_at: nil).not_expired }

  scope :persistent, -> { where("? = ANY(scopes)", "refresh") }

  # The permissible policy associated with this access token. Can be null if there's no policy.
  # Will be destroyed alongside this access token (slight smell - this is used elsewhere *but* this is the only model
  # that will persist).
  belongs_to :permissible_policy, class_name: "OAuth::PermissiblePolicy", optional: true

  def self.matching_token_for(application, resource_owner, scopes)
    result = super

    # If a permissible policy is defined, allow the user to regenerate the token to change security settings.
    return nil if result&.permissible_policy_id.present?

    # If we're requesting a scope that potentially requires a new permissible policy (but doesn't have one for some
    # reason), require a new token be used.
    # FIXME: This should be done at the access token level instead.
    return nil if scopes.any? { |s| %w[character character:all user:social].include?(s) }

    result
  end
end
