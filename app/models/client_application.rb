class ClientApplication < ApplicationRecord
  include HasUploadAttachment

  has_upload_attachment :icon,
    content_types: %w[image/png image/jpeg image/webp image/gif],
    max_size:      2.megabytes

  belongs_to :owner, polymorphic: true, optional: true

  has_one :profile, class_name: "ClientApplication::Profile", dependent: :destroy, required: true, autosave: true,
          foreign_key: :application_id, inverse_of: :application

  has_many :oauth_clients, class_name: "ClientApplication::OAuthClient", dependent: :destroy,
           foreign_key: :application_id, inverse_of: :application
  has_many :acls, class_name: "ClientApplication::AccessControlList", dependent: :destroy,
           foreign_key: :application_id, inverse_of: :application

  # Apps permitted to request a JWT on behalf of this app.
  has_and_belongs_to_many :obo_authorizations, class_name: "ClientApplication",
                          join_table: "client_application_obo_authorizations",
                          foreign_key: "audience_id",
                          association_foreign_key: "authorized_party_id"

  # Apps that this app can request a JWT for.
  has_and_belongs_to_many :obo_authorized_by, class_name: "ClientApplication",
                          join_table: "client_application_obo_authorizations",
                          foreign_key: "authorized_party_id",
                          association_foreign_key: "audience_id"

  validates_associated :profile
  accepts_nested_attributes_for :profile, update_only: true

  validate :validate_owner_has_mfa, on: :create

  def profile
    super || build_profile
  end

  def icon_url(derivative: nil)
    icon&.url(derivative: derivative) || "https://api.dicebear.com/9.x/initials/png?seed=#{self.name}&backgroundType=gradientLinear"
  end

  def verified?
    self.verified_at.present?
  end

  def usable_by?(user)
    return true unless self.private?
    return true if owner.is_a?(User) && owner == user

    if owner.is_a?(Team)
      return true if owner.direct_members.include?(user)
      return true if owner.antecedent_memberships.admins.where(user_id: user.id).exists?
    end

    user_match = acls.find_by(principal: user)
    if user_match
      return !user_match.deny?
    end

    acls.where(principal_type: "Team").order(deny: :desc).each do |a|
      team = a.principal
      next if team.nil?

      if team.all_members(include_antecedents: !a.deny?, include_descendants: a.include_team_descendants).include?(user)
        return !a.deny?
      end
    end

    false
  end

  def has_entitlement?(name)
    entitlements.include?(name.to_s)
  end

  def validate_owner_has_mfa
    return unless owner.is_a?(User)

    unless owner.mfa_enabled_or_passwordless?
      errors.add(:owner, :mfa_required, message: "must be protected with MFA.")
    end
  end
end