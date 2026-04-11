class Team::Membership < ApplicationRecord
  enum :role, { admin: "admin", manager: "manager", developer: "developer", member: "member", invited: "invited", blocked: "blocked" },
       scopes: false

  scope :admins, -> { where(role: [:admin]) }
  scope :managers, -> { where(role: %i[admin manager]) }
  scope :developers, -> { where(role: %i[admin manager developer]) }
  scope :active, -> { where(role: %i[admin manager developer member]) }

  belongs_to :team, class_name: "Team", inverse_of: :direct_memberships
  belongs_to :user, class_name: "User", inverse_of: :team_memberships

  validates :user_id, uniqueness: { scope: :team_id }
  validate :validate_team_after_change
  before_destroy :ensure_team_has_admin

  def self.generate_case_for_role_ranking(table_alias = self.table_name)
    mapping = self.roles
    size = mapping.size
    when_thens = mapping.keys.each_with_index.map do |role_name, idx|
      "WHEN #{ActiveRecord::Base.connection.quote(role_name.to_s)} THEN #{size - idx}"
    end

    "CASE #{table_alias}.role #{when_thens.join(' ')} ELSE 0 END"
  end

  private

  def validate_team_after_change
    # For root teams, check that there will still be at least one admin after this change
    return if team.parent_id.present?

    # Simulate the team's memberships after this change is applied.
    # `team.direct_memberships` is a DB query and does not include unsaved records.
    memberships = team.direct_memberships.to_a

    if new_record?
      # New record isn't in the DB yet - include it in the simulated state
      memberships << self
    else
      # Existing record - swap the stale DB version with self (which has the pending role)
      memberships.map! { |m| m.id == id ? self : m }
    end

    return if memberships.any? { |m| m.role.to_s == "admin" }

    errors.add(:base, "Root teams must have at least one admin")
  end

  def ensure_team_has_admin
    return if team.parent_id.present?
    return unless admin?
    return if team.direct_memberships.admins.where.not(id: id).exists?

    errors.add(:base, "Cannot remove the last team admin")
    throw :abort
  end
end