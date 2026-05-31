class ClientApplication < ApplicationRecord
  include HasUploadAttachment

  ENTITLEMENTS = [
    :code_signing_certificates,  # Allowed to issue code signing certificates.
    :custom_background,          # Allowed to use a custom OAuth background. Automatic for verified apps.
    :flarestone_force_fresh,     # Allowed to bypass Flarestone caches.
    :internal                    # Allowed to use scopes tagged as "internal."
  ].freeze

  has_upload_attachment :icon,
                        content_types: %w[image/png image/jpeg image/webp image/gif],
                        max_size: 2.megabytes,
                        validate: [
                          ShrineValidations::AnimationDetector::VALIDATE_NOT_ANIMATED
                        ],
                        derivatives: lambda { |pipeline|
                          {
                            large: pipeline.resize_to_fill!(256, 256)
                          }
                        }

  has_upload_attachment :oauth_background, content_types: %w[image/png image/jpeg],
                        max_size: 5.megabytes,
                        derivatives: lambda { |pipeline|
                          {
                            hd: pipeline.resize_to_limit!(3840, 2160),
                            thumb: pipeline.resize_to_fill!(160, 90)
                          }
                        }

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

  validates :entitlements, array: { inclusion: { in: ENTITLEMENTS.map(&:to_s) } }

  validate :validate_owner_has_mfa, on: :create
  validate :validate_oauth_background_requires_verification

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
      return true if owner.antecedent_memberships.admins.exists?(user_id: user.id)
    end

    user_match = acls.find_by(principal: user)
    return !user_match.deny? if user_match

    acls.where(principal_type: "Team").order(deny: :desc).each do |a|
      team = a.principal
      next if team.nil?

      if team.all_members(include_antecedents: !a.deny?, include_descendants: a.include_team_descendants).include?(user)
        return !a.deny?
      end
    end

    false
  end

  def entitlement_granted?(name)
    entitlements.include?(name.to_s)
  end

  def can_use_custom_background?
    verified? || entitlement_granted?(:custom_background)
  end

  def validate_oauth_background_requires_verification
    return if can_use_custom_background?
    return if oauth_background.nil? || oauth_background.persisted?

    errors.add(:oauth_background, :unverified, message: "can only be set on verified applications.")
  end

  def validate_owner_has_mfa
    return unless owner.is_a?(User)

    return if owner.mfa_enabled_or_passwordless?

    errors.add(:owner, :mfa_required, message: "must be protected with MFA.")
  end
end
