module OAuth::BuildsPermissiblePolicies
  extend ActiveSupport::Concern

  def build_permissible_policy
    policy = OAuth::PermissiblePolicy.new

    build_character_policy_rules(policy)
    build_identity_policy_rules(policy)

    policy
  end

  def build_character_policy_rules(policy)
    character_ids = params[:characters] || []
    share_new_characters = params[:share_new_characters].present?

    objects = CharacterRegistration.verified
                                   .where(user_id: current_resource_owner.id)
                                   .includes(:character)

    objects = if share_new_characters
                # Filter to only characters that were *not* selected, so we can deny access to them.
                objects.where.not(character: { lodestone_id: character_ids })
              else
                # Otherwise, filter to only selected characters.
                objects.where(character: { lodestone_id: character_ids })
              end

    logger.info("Creating rules for #{objects.count} characters.")

    objects.each do |character|
      # Remember: deny happens only to the inverse selection
      policy.rules.new(resource: character, deny: share_new_characters)
    end
  end

  def build_identity_policy_rules(policy)
    identity_ids = params[:social_identities] || []
    share_new_identities = params[:share_new_identities].present?

    objects = User::SocialIdentity.where(user_id: current_resource_owner.id)

    objects = if share_new_identities
                # Filter to only identities that were *not* selected, so we can deny access to them.
                objects.where.not(id: identity_ids)
              else
                # Otherwise, filter to only selected characters.
                objects.where(id: identity_ids)
              end

    logger.info("Creating rules for #{objects.count} identities.")

    objects.each do |identity|
      # Remember: deny happens only to the inverse selection
      policy.rules.new(resource: identity, deny: share_new_identities)
    end
  end
end
