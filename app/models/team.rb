class Team < ApplicationRecord
  include HasUploadAttachment

  TEAM_DEPTH_LIMIT = 5
  TEAM_SUBTEAM_LIMIT = 5

  has_one :profile, class_name: "Team::Profile", dependent: :destroy, required: true, autosave: true

  has_upload_attachment :icon,
                        content_types: %w[image/png image/jpeg image/webp image/gif],
                        max_size: 2.megabytes,
                        validate: [
                          ShrineValidations::AnimationDetector::VALIDATE_NOT_ANIMATED
                        ],
                        derivatives: ->(pipeline) {
                          {
                            large:  pipeline.resize_to_fill!(256, 256)
                          }
                        }

  belongs_to :parent, class_name: "Team", optional: true
  has_many :subteams, class_name: "Team", foreign_key: "parent_id", inverse_of: :parent

  # Note: memberships don't have any callbacks we care about, so just dropping is safe (for now)
  has_many :direct_memberships, class_name: "Team::Membership", dependent: :delete_all
  has_many :direct_members, through: :direct_memberships, source: :user

  accepts_nested_attributes_for :direct_memberships

  has_many :invite_links, class_name: "Team::InviteLink", dependent: :destroy

  has_many :client_applications, class_name: "ClientApplication", as: :owner

  validates :name, presence: true
  validate :validate_subteam_or_has_admin

  validate :team_recursion_control
  before_destroy :validate_deletion

  before_create do
    build_profile
    true
  end

  def profile
    super || build_profile
  end

  def icon_url(derivative: nil)
    icon&.url(derivative: derivative) || "https://api.dicebear.com/9.x/initials/png?seed=#{self.name}&backgroundType=gradientLinear"
  end

  def active_memberships
    self.direct_memberships.active
  end

  def active_members
    User.where(id: active_memberships.reselect(:user_id))
        .reorder(nil)
  end

  def antecedent_team_ids
    team_ids = []
    current = self.parent

    while current
      team_ids << current.id
      current = current.parent
    end

    team_ids
  end

  def antecedent_memberships
    self.resolve_antecedent_memberships
  end

  def antecedent_members
    User.where(id: antecedent_memberships.reselect(:user_id))
        .reorder(nil)
  end

  def descendant_team_ids
    # teams can't have children without a known self id, so we can be lazy
    return [] if self.id.blank?

    team_ids = []
    frontier = Team.where(parent_id: self.id).ids

    while frontier.any?
      team_ids.concat(frontier)
      frontier = Team.where(parent_id: frontier).ids
    end

    team_ids
  end

  def descendant_memberships
    Team::Membership.where(team_id: descendant_team_ids).active
  end

  def descendant_members
    User.where(id: descendant_memberships.reselect(:user_id))
        .reorder(nil)
  end

  def all_members(include_antecedents: true, include_descendants: false)
    scope = User.where(id: self.direct_memberships.reselect(:user_id))

    scope = scope.or(User.where(id: antecedent_memberships.reselect(:user_id))) if include_antecedents
    scope = scope.or(User.where(id: descendant_memberships.reselect(:user_id))) if include_descendants

    scope.distinct
  end

  def readonly?
    super || (!new_record? && is_special_id?)
  end

  def verified?
    self.verified_at.present?
  end

  protected def resolve_antecedent_memberships(managers_only: false, recursing: false)
    base = if recursing
             managers_only ? self.direct_memberships.managers : self.direct_memberships.active
           else
             Team::Membership.none
           end

    if self.parent
      only_search_managers = managers_only || !self.inherit_parent_memberships
      antecedents = self.parent.resolve_antecedent_memberships(managers_only: only_search_managers, recursing: true)

      antecedents.or(base)
    else
      base
    end
  end

  def deletion_block_reason
    errors = deletion_check
    errors.first&.dig(:message)
  end

  def can_be_deleted?
    deletion_check.empty?
  end

  # Returns an array of hashes with code and message if deletion is blocked, empty array otherwise
  # @return [Array<Hash{code: Symbol, message: String}>]
  private def deletion_check
    deletion_errors = []

    if is_special_id?
      deletion_errors << { code: :system_team, message: "This team is marked as a system team and cannot be deleted." }
    end

    if verified?
      deletion_errors << { code: :verified_team, message: "This team has been verified and cannot be deleted." }
    end

    if subteams.any?
      deletion_errors << { code: :has_subteams, message: "This team has child teams and cannot be deleted." }
    end

    deletion_errors
  end

  private def validate_deletion
    checks = deletion_check
    if checks.present?
      checks.each do |check|
        errors.add(:base, check[:message])
      end
      throw :abort
    end
  end

  # Check if this ID is a special UUID of the form 00000000-0000-8000-8f0f-0000xxxxxxxx
  # where x is any hex digit. This is used to mark internal or system teams that should
  # not be edited by the app.
  def is_special_id?
    return false if self.id.nil?

    (self.id.gsub("-", "").to_i(16) >> 32) == 0x8000_8f0f_0000
  end

  private def validate_subteam_or_has_admin
    return unless new_record?
    return unless self.parent_id.nil?

    # Consider in-memory built memberships (including nested attributes) so validation
    # works before persistence. Avoid querying only the DB.
    has_admin = self.direct_memberships.any? { |m| m.role.to_s == "admin" }
    errors.add(:base, "Root teams must have at least one admin") unless has_admin
  end

  private def check_team_loop
    return if self.parent_id.nil? || self.id.nil?

    if self.parent_id == self.id
      errors.add(:parent_id, "cannot be the same as the team itself")
      return
    end

    children = Team.where(parent_id: self.id)
    while children.any?
      if children.any? { |t| t.id == self.parent_id }
        errors.add(:parent_id, "cannot create a recursive hierarchy")
      end

      children = Team.where(parent_id: children.pluck(:id))
    end
  end

  private def team_recursion_control
    return if self.parent_id.blank?

    # ensure we don't have a loop before doing our recursion checks
    self.check_team_loop
    return if errors.any?

    if Team.where(parent_id: self.parent_id).count >= TEAM_SUBTEAM_LIMIT
      errors.add(:parent_id, "cannot have more than #{TEAM_SUBTEAM_LIMIT} direct subteams")
    end

    # Disallow depth of n+ (i.e., great-grandchildren)
    if antecedent_team_ids.length >= TEAM_DEPTH_LIMIT
      errors.add(:parent_id, "cannot be more than #{TEAM_DEPTH_LIMIT} levels deep")
    end
  end
end
