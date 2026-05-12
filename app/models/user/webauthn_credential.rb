class User::WebauthnCredential < ApplicationRecord
  belongs_to :user

  belongs_to :device_class, class_name: "Webauthn::DeviceClass", foreign_key: :aaguid, optional: true,
             inverse_of: false

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :nickname, presence: true, uniqueness: { scope: :user_id }
  validates :sign_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :validate_user_has_webauthn_id

  def validate_user_has_webauthn_id
    errors.add(:user, "does not have a webauthn id") unless user.webauthn_id
  end
end
