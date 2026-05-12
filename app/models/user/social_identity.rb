class User::SocialIdentity < ApplicationRecord
  belongs_to :user
  validates :external_id, uniqueness: { scope: [:provider] }

  alias_attribute :uid, :external_id

  def friendly_name
    name || nickname || email || external_id
  end

  # Merges an incoming authentication hash from OmniAuth, and saves the record.
  # @param [OmniAuth::AuthHash] auth The AuthHash from OmniAuth
  def merge_auth_hash(auth, save_email: false)
    self.name = auth["info"]["name"]
    self.nickname = auth["info"]["nickname"]
    self.email = auth["info"]["email"] || email if save_email

    self.raw_info = auth["extra"]["raw_info"]

    save
  end

  def touch_used_at
    self.last_used_at = Time.current
    save(touch: false)
  end
end
