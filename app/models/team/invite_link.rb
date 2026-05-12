class Team::InviteLink < ApplicationRecord
  belongs_to :team, inverse_of: :invite_links

  after_initialize :generate_invite_key

  validates :invite_key, presence: true, uniqueness: true
  validates :target_role, presence: true, inclusion: { in: %w[member developer] }

  validates :usage_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :validate_expiration

  scope :active, lambda {
    where(enabled: true)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
      .where("usage_limit IS NULL OR usage_count < usage_limit")
  }

  def active?
    enabled && !expired? && !exhausted?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def exhausted?
    usage_limit.present? && usage_count >= usage_limit.to_i
  end

  def unlimited?
    usage_limit.nil? && expires_at.nil?
  end

  private def generate_invite_key
    self.invite_key = SecureRandom.base58(16) if invite_key.blank?
  end

  private def validate_expiration
    return if expires_at.blank?

    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
    errors.add(:expires_at, "cannot be more than 1 month in the future") if expires_at > 1.month.from_now
  end
end
