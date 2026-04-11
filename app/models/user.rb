class User < ApplicationRecord
  include OmniauthAuthenticable
  include SystemRoleable
  include User::TeamAssociations

  # ZXCVBN config
  include PasswordStrengthValidatable
  self.zxcvbn_user_inputs = %i[email display_name]
  self.zxcvbn_static_inputs = %w[xivauth ffxiv eorzea]

  devise :database_authenticatable, :registerable,
         :confirmable, :trackable, :recoverable,
         :rememberable, :validatable,
         :omniauthable
  devise :pwned_password unless Rails.env.development? || Rails.env.test?

  validates :email, exclusion: { in: Users::SessionsHelper::RANDOM_NPC_EMAILS, message: " is an NPC's email.... Nice try." }
  validates :email, email: true
  validates :unconfirmed_email, email: true, allow_blank: true

  has_many :social_identities, class_name: "User::SocialIdentity", dependent: :destroy
  has_many :character_registrations, dependent: :destroy

  has_many :webauthn_credentials, class_name: "User::WebauthnCredential", dependent: :destroy
  has_one :totp_credential, class_name: "User::TotpCredential", dependent: :destroy
  validates :webauthn_id, uniqueness: true, allow_nil: true

  has_one :profile, class_name: "User::Profile", dependent: :destroy, required: true, autosave: true
  validates_associated :profile
  accepts_nested_attributes_for :profile, update_only: true

  has_many :team_memberships, class_name: "Team::Membership", dependent: :destroy
  has_many :teams, through: :team_memberships, source: :team

  has_many :oauth_authorizations, class_name: "OAuth::AccessToken", foreign_key: "resource_owner_id",
           inverse_of: :resource_owner, dependent: :destroy

  has_many :pki_issued_certificates, class_name: "PKI::IssuedCertificate",
           as: :subject  # no dependent: - records survive as a permanent audit log

  before_destroy :revoke_pki_certificates_on_destroy

  def profile
    super || build_profile
  end

  def admin?
    self.role? :admin
  end

  # Check if the user has permission to access developer functions, like the ability to register OAuth applications.
  def developer?
    self.role?(:developer)
  end

  def unverified_character_allowance
    5
  end

  # Checks whether the user has MFA defined on their account.
  def mfa_enabled?
    webauthn_credentials.any? || totp_credential&.otp_enabled || false
  end

  # Check whether the user is passwordless or has MFA.
  # Used for activities that require MFA.
  def mfa_enabled_or_passwordless?
    !has_password? || mfa_enabled?
  end

  # Check if the user has a defined encrypted password. If not, this user is considered oauth-only and cannot
  # use certain login features.
  def has_password?
    self.encrypted_password.present?
  end

  def display_name
    profile.display_name
  end

  def avatar_url
    gravatar_url(144)
  end

  def gravatar_url(size = 32, fallback: "retro", rating: "pg")
    hash = EmailAddress.reference(email)
    "https://secure.gravatar.com/avatar/#{hash}.png?s=#{size}&d=#{fallback}&r=#{rating}"
  end

  # Overrides Devise's Validatable#password_required?
  def password_required?
    # Don't require a password for validation for new users if a social identity is present
    return false if !persisted? && !social_identities.empty?

    # Don't require a password for validation if the user does not have a password
    return false if persisted? && !has_password?

    super
  end

  def set_initial_password(password, confirmation)
    # This method cannot be used to set a new password.
    return false if has_password?

    update(
      password: password,
      password_confirmation: confirmation
    )
  end

  def has_verified_characters?
    if character_registrations.loaded?
      character_registrations.any?(&:verified?)  # N+1
    else
      character_registrations.verified.exists?
    end
  end

  # Get the list of providers that can be used for authentication purposes.
  def self.omniauth_login_providers
    social_only_providers = [:patreon]

    omniauth_providers - social_only_providers
  end

  # Get a list of configured Omniauth providers that can be bound to this user.
  # Used to generate routes and other systems, so will include providers that cannot be used for authentication.
  def self.omniauth_providers
    Devise.omniauth_configs.keys & (Rails.application.credentials[:oauth]&.keys || [])
  end

  def self.signup_permitted?
    Flipper.enabled? :user_signups
  end

  private def revoke_pki_certificates_on_destroy
    pki_issued_certificates.active.find_each { |c| c.revoke!(reason: "cessation_of_operation") }
  end
end
