class Abilities::UserAbility
  include CanCan::Ability

  def initialize(user)
    can :manage, CharacterRegistration, user_id: user.id
    can :manage, User::SocialIdentity, user_id: user.id

    can :use, ClientApplication do |a|
      a.usable_by?(user)
    end

    can :manage, ClientApplication do |a|
      if a.owner.is_a?(User)
        a.owner_id == user.id
      elsif a.owner.is_a?(Team)
        a.owner.direct_memberships.developers.where(user_id: user.id).any? ||
          a.owner.antecedent_memberships.developers.where(user_id: user.id).any?
      else
        false
      end
    end

    # Associated with the team (any active member). Used for basic access checks.
    can :use, Team do |t|
      t.direct_memberships.active.where(user_id: user.id).any? ||
        t.antecedent_memberships.where(user_id: user.id).any?
    end

    # View team details (show page). Developers, managers, and admins only.
    can :show, Team do |t|
      t.direct_memberships.developers.where(user_id: user.id).any? ||
        t.antecedent_memberships.developers.where(user_id: user.id).any?
    end

    can :create_apps, Team do |t|
      t.direct_memberships.developers.where(user_id: user.id).any? ||
        t.antecedent_memberships.developers.where(user_id: user.id).any?
    end

    # Make changes to the team itself (name, metadata)
    # Manage users of the team, and child teams.
    can %i[update manage_users], Team do |t|
      t.direct_memberships.managers.where(user_id: user.id).any? ||
        t.antecedent_memberships.managers.where(user_id: user.id).any?
    end

    # Only admins can create subteams at present. Just defining this rule for clarity, as it's covered in the
    # wildcard. NOTE: Also set as part of `load_parent_teams` in TeamsController!
    can :create_subteam, Team do |_t|
      false
    end

    # Full management (wildcard). Only true admins. Covers :destroy and any other unspecified actions.
    can :manage, Team do |t|
      t.direct_memberships.admins.where(user_id: user.id).any? ||
        t.antecedent_memberships.admins.where(user_id: user.id).any?
    end

    # EDGE CASE: Block admins from deleting a subteam if they're a direct admin of that team.
    # Logic here is that a subteam shouldn't be able to destroy itself as it was created at a higher level. Teams
    # further down the tree are fair game, though.
    cannot :destroy, Team do |t|
      t.direct_memberships.admins.where(user_id: user.id).any? && t.parent.present?
    end

    # PKI certificates: read and revoke own certs.
    # User-subject certs: simple column condition.
    can %i[read revoke], PKI::IssuedCertificate, subject_type: "User", subject_id: user.id

    # CharacterRegistration-subject certs: block check (no simple hash condition due to polymorphic subject).
    can %i[read revoke], PKI::IssuedCertificate do |cert|
      cert.subject_type == "CharacterRegistration" &&
        user.character_registrations.verified.exists?(id: cert.subject_id)
    end
  end
end
