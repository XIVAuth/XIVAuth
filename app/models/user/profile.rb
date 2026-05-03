class User::Profile < ApplicationRecord
  self.primary_key = :user_id

  belongs_to :user, class_name: "User", touch: true

  # TODO: maybe this should be a database table...
  DISPLAY_NAME_BLOCKED_WORDS = [
    "auth", "admin", "root", "system", "oauth", "security", "dalamud", "support", "moderator",
    /ff[-.@_ ]*(xiv|14)/, /square([-.@_ ]*e)?nix/, /yoshi[-.@_ ]*p/, /naoki+[-.@_ ]*yoshi(da)?/,
    /kaz[-.@_ ]*wolfe?/, /goa+ts?/
  ].freeze

  validates :display_name, length: { in: 4..32 }, presence: true
  validates :display_name, format: { with: /\A[ a-zA-Z0-9._\-]+\z/,
                                     message: "only allows alphanumerics, underscores, spaces, periods, and dashes." }
  validates :display_name, format: { without: /#{Regexp.union(DISPLAY_NAME_BLOCKED_WORDS).source}/i,
                                     message: "cannot be used" }, if: :display_name_changed?

  def has_feature?(feature_name)
    self.preferences&.dig("features", feature_name.to_s, "enabled") == true
  end

  def set_feature_enabled(feature_name, enabled)
    self.preferences ||= {}
    self.preferences[:features] ||= {}
    self.preferences[:features][feature_name] ||= {}
    self.preferences[:features][feature_name][:enabled] = enabled
  end

  def set_feature_enabled!(feature_name, enabled)
    set_feature_enabled(feature_name, enabled)
    save!
  end
end
