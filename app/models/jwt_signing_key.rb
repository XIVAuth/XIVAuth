class JwtSigningKey < ApplicationRecord
  DEFAULT_ALGORITHM = "EdDSA".freeze

  encrypts :private_key

  validates :name, presence: true
  validates :type, presence: true

  validates :private_key, presence: true

  scope :active, -> { where(enabled: true).where("expires_at IS NULL or expires_at >= ?", Time.current) }

  attr_readonly :public_key, :raw_public_key, :raw_private_key, :jwk

  def to_param
    name
  end

  def raw_public_key
    self[:public_key]
  end

  def raw_private_key
    self[:private_key]
  end

  def jwk
    JWT::JWK.new(private_key, use: "sig", kid: name, **extra_jwk_fields)
  end

  def supported_algorithms
    raise NoMethodError, "Must be implemented by subclass"
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    enabled? && !expired?
  end

  def self.jwks
    jwk_set = active.map(&:jwk)

    JWT::JWK::Set.new(jwk_set)
  end

  def self.preferred_key_for_algorithm(algorithm_name)
    alg_type = JWT::JWA.find(algorithm_name).class
    case alg_type.to_s
    when "JWT::JWA::Rsa", "JWT::JWA::Ps"
      JwtSigningKeys::RSA.active.first
    when "JWT::EdDSA::Algo"
      JwtSigningKeys::Ed25519.active.first
    when "JWT::JWA::Hmac", "JWT::JWA::HmacRbNaCl"
      JwtSigningKeys::HMAC.active.first
    when "JWT::JWA::Ecdsa"
      JwtSigningKeys::ECDSA.preferred_key_for_algorithm(algorithm_name)
    end
  end

  private def extra_jwk_fields
    fields = {
      algs: supported_algorithms
    }

    fields[:exp] = expires_at.to_i if expires_at.present?

    fields
  end

  private def keys_changed?
    will_save_change_to_private_key? || will_save_change_to_public_key?
  end
end
