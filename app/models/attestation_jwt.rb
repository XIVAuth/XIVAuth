class AttestationJwt
  include ActiveModel::Model
  include ActiveModel::Validations

  # Attributes for validation and access
  attr_accessor :algorithm

  # Custom error for signed tokens
  class SignedTokenError < StandardError; end

  # Validations for JWTs we're generating
  validate :validate_signing_key_active
  validate :validate_signing_key_present
  validate :validate_algorithm_compatible

  validate :validate_iat_in_past
  validate :validate_exp_not_expired
  validate :validate_exp_within_key_lifetime
  validate :validate_exp_after_iat
  validate :validate_exp_after_nbf
  validate :validate_issuer
  validate :validate_azp_authorized_for_aud, if: :azp_present?

  def initialize(body_attrs: { }, header_attrs: { }, **helper_fields)
    super()
    @jwt_token = JWT::Token.new(
      payload: body_attrs.dup.stringify_keys,
      header: header_attrs.dup.stringify_keys
    )
    @signing_key = nil
    @exp_duration = nil
    @audience_app = nil
    @azp_app = nil

    helper_fields.each do |field, value|
      next if value.nil?

      public_send("#{field}=", value) if respond_to?("#{field}=")
    end

    set_default_parameters
  end

  # Set the default algorithm and signing key when creating a new JWT
  private def set_default_parameters
    # Only set if not already set
    self.algorithm = JwtSigningKey::DEFAULT_ALGORITHM if algorithm.blank?

    self.signing_key = JwtSigningKey.preferred_key_for_algorithm(algorithm) if @signing_key.blank?

    body["iss"] = ENV.fetch("APP_URL", "https://xivauth.net") if issuer.blank?

    body["jti"] = SecureRandom.urlsafe_base64(24, padding: false) if jwt_id.blank?

    # Set jku (JWK Set URL) header if not already set
    return if header["jku"].present?

    jku_url = "#{ENV.fetch('APP_URL', 'https://xivauth.net')}/api/v1/jwt/jwks"
    header["jku"] = jku_url
  end

  # Check if the token has been signed
  def signed?
    @encoded_token.present?
  end

  # Prevent mutations after signing
  def ensure_not_signed!
    raise SignedTokenError, "Cannot mutate a signed JWT" if signed?
  end

  # ============================================================================
  # Hash-Style Field Access
  # ============================================================================

  # Provides hash-style access to headers
  delegate :header, to: :@jwt_token

  # Provides hash-style access to the body
  def body
    @jwt_token.payload
  end

  # ============================================================================
  # Signing Key Helper
  # Note: kid header is automatically set from signing_key.name during signing
  # ============================================================================

  attr_reader :signing_key

  def signing_key=(key)
    ensure_not_signed!
    raise ArgumentError, "signing_key must be a JwtSigningKey or nil" unless key.nil? || key.is_a?(JwtSigningKey)

    @signing_key = key
  end

  # ============================================================================
  # Header Field Helpers
  # ============================================================================

  # Claim Type (cty header)
  def claim_type
    header["cty"]
  end

  def claim_type=(value)
    ensure_not_signed!
    header["cty"] = value
  end

  # ============================================================================
  # Common Field Helpers
  # ============================================================================

  # Issued At (Time or Unix timestamp)
  # Only will return a Time if one was explicitly set. If nil, one will be encoded at signing.
  def issued_at
    value = body["iat"]
    return nil unless value.is_a?(Integer)

    Time.zone.at(value)
  end

  def issued_at=(value)
    ensure_not_signed!
    timestamp = case value
                when Integer
                  value
                when DateTime, Time, Date
                  value.to_time.to_i
                else
                  raise ArgumentError, "issued_at must be a Time, Time, Date, or Unix timestamp (Integer)"
                end
    body["iat"] = timestamp
  end

  # When this JWT is slated to expire.
  # If expires_in was used, this will return a preview calculated from issued_at or the current time.
  def expires_at
    if @exp_duration.present?
      iat = body["iat"] || Time.now.to_i
      Time.zone.at(iat + @exp_duration.to_i)
    else
      value = body["exp"]
      return nil unless value.is_a?(Integer)

      Time.zone.at(value)
    end
  end

  def expires_at=(value)
    ensure_not_signed!
    case value
    when Integer
      @exp_duration = nil
      timestamp = clamp_to_key_expiration(value)
      body["exp"] = timestamp
    when DateTime, Time, Date
      @exp_duration = nil
      timestamp = value.to_time.to_i
      timestamp = clamp_to_key_expiration(timestamp)
      body["exp"] = timestamp
    when nil
      @exp_duration = nil
      body["exp"] = nil
    else
      raise ArgumentError, "expires_at must be a DateTime, Time, Date, nil, or Unix timestamp (Integer)"
    end
  end

  # Expiration Duration (set-only helper)
  # Sets expires_at relative to issued_at at sign time
  def expires_in=(value)
    ensure_not_signed!
    case value
    when ActiveSupport::Duration
      @exp_duration = value
      # Duration will be resolved and clamped at sign time
      body.delete("exp")
    when Integer
      @exp_duration = value.seconds
      body.delete("exp")
    when nil
      @exp_duration = nil
      body.delete("exp")
    else
      raise ArgumentError, "expires_in must be an ActiveSupport::Duration, an Integer, or nil."
    end
  end

  # Clamps a Unix timestamp to not exceed the signing key's expiration
  private def clamp_to_key_expiration(timestamp)
    key = signing_key
    return timestamp if key.blank? || key.expires_at.blank?

    key_exp_timestamp = key.expires_at.to_i
    [timestamp, key_exp_timestamp].min
  end

  # Subject
  def subject
    body["sub"]
  end

  def subject=(value)
    ensure_not_signed!
    body["sub"] = value
  end

  # Audience
  # Can be set with a ClientApplication object (auto-formats to URL) or any string
  def audience
    @audience_app || body["aud"]
  end

  def audience=(value)
    ensure_not_signed!
    case value
    when ClientApplication
      @audience_app = value
      # URL encoding happens in set_managed_fields during signing
    when String
      @audience_app = nil
      body["aud"] = value
    when nil
      @audience_app = nil
      body["aud"] = nil
    else
      raise ArgumentError, "audience must be a ClientApplication, String, or nil"
    end
  end

  # Authorized Party (always a ClientApplication)
  # Represents the app authorized to request tokens on behalf of another app
  # Stored in the same URL format as audience: https://xivauth.net/applications/{application_id}
  def authorized_party
    @azp_app || body["azp"]
  end

  def authorized_party=(value)
    ensure_not_signed!
    case value
    when ClientApplication
      @azp_app = value
      # URL encoding happens in set_managed_fields during signing
    when nil
      @azp_app = nil
      body["azp"] = nil
    else
      raise ArgumentError, "authorized_party must be a ClientApplication or nil"
    end
  end

  # Issuer
  def issuer
    body["iss"]
  end

  def issuer=(value)
    ensure_not_signed!
    body["iss"] = value
  end

  # JWT ID
  def jwt_id
    body["jti"]
  end

  def jwt_id=(value)
    ensure_not_signed!
    body["jti"] = value
  end

  # Nonce
  def nonce
    body["nonce"]
  end

  def nonce=(value)
    ensure_not_signed!
    body["nonce"] = value
  end

  # Not Before (Time or Unix timestamp)
  def not_before
    value = body["nbf"]
    return nil unless value.is_a?(Integer)

    Time.zone.at(value)
  end

  def not_before=(value)
    ensure_not_signed!
    timestamp = case value
                when Integer
                  value
                when DateTime, Time, Date
                  value.to_time.to_i
                else
                  raise ArgumentError, "not_before must be a DateTime, Time, Date, or Unix timestamp (Integer)"
                end
    body["nbf"] = timestamp
  end

  # ============================================================================
  # Rendering (Signing)
  # ============================================================================

  # Hook method for setting managed fields before validation/signing
  # Subclasses can override to add their own managed fields
  private def set_managed_fields
    # Set temporal fields
    body["iat"] = Time.now.to_i if issued_at.blank?

    # Resolve expires_in duration if needed
    if @exp_duration.present?
      iat_timestamp = body["iat"]
      exp_timestamp = iat_timestamp + @exp_duration.to_i
      exp_timestamp = clamp_to_key_expiration(exp_timestamp)
      body["exp"] = exp_timestamp
    end

    # Set cryptographic fields
    key = signing_key
    header["kid"] = key.name if key.present?
    header["alg"] = @algorithm if @algorithm.present?

    # Set application fields.
    body["aud"] = application_url_for(@audience_app.id) if @audience_app.present?
    body["azp"] = application_url_for(@azp_app.id) if @azp_app.present?
  end

  private def sign!
    return @encoded_token if signed?

    set_managed_fields

    raise ActiveModel::ValidationError, self unless valid?

    key = signing_key
    @jwt_token.sign!(key: key.private_key, algorithm: @algorithm)
    @encoded_token = @jwt_token.jwt

    @encoded_token
  end

  # ============================================================================
  # Token Access (triggers signing if needed)
  # ============================================================================

  def token
    return @encoded_token if signed?

    sign!
  end

  # ============================================================================
  # Validation Methods
  # ============================================================================

  # Helper methods for conditional validations
  private def azp_present?
    @azp_app.present? || body["azp"].present?
  end

  private def validate_signing_key_present
    return if signing_key.present?

    errors.add(:signing_key, :blank, message: "must be present")
  end

  private def validate_algorithm_compatible
    key = signing_key
    return if key.blank? || @algorithm.blank?

    return if key.supported_algorithms.include?(@algorithm)

    errors.add(
      :algorithm, :invalid_algorithm,
      message: "not supported by signing key '#{key.name}'. Supported: #{key.supported_algorithms.join(', ')}"
    )
  end

  private def validate_signing_key_active
    key = signing_key
    return if key.blank?

    errors.add(:signing_key, :signing_key_disabled, message: "was disabled") unless key.enabled?

    return unless key.expired?

    errors.add(:signing_key, :signing_key_expired, message: "has expired")
  end

  private def validate_iat_in_past
    iat_value = issued_at
    return if iat_value.blank?

    current_time = Time.current
    return unless iat_value > current_time

    errors.add(
      :issued_at, :issued_in_future,
      message: "is in the future"
    )
  end

  private def validate_exp_not_expired
    exp_value = expires_at
    return if exp_value.blank?

    current_time = Time.current
    return unless exp_value < current_time

    errors.add(:expires_at, :token_expired, message: "is in the past")
  end

  private def validate_exp_within_key_lifetime
    exp_value = body["exp"]
    return if exp_value.blank?

    key = signing_key
    return if key.blank? || key.expires_at.blank?

    return unless exp_value > key.expires_at.to_i

    errors.add(:expires_at, :exceeds_key_expiration, message: "exceeds signing key expiration")
  end

  private def validate_exp_after_iat
    exp_value = body["exp"]
    iat_value = body["iat"]
    return if exp_value.blank? || iat_value.blank?

    return unless exp_value <= iat_value

    errors.add(:expires_at, :exp_before_iat, message: "must be after issued_at")
  end

  private def validate_exp_after_nbf
    exp_value = body["exp"]
    nbf_value = body["nbf"]
    return if exp_value.blank? || nbf_value.blank?

    return unless exp_value <= nbf_value

    errors.add(:expires_at, :exp_before_nbf, message: "must be after not_before")
  end

  private def validate_issuer
    issuer_value = issuer
    expected_issuer = ENV.fetch("APP_URL", "https://xivauth.net")

    if issuer_value.blank?
      errors.add(:issuer, :missing_issuer, message: "is not set")
      return
    end

    return if issuer_value.start_with?(expected_issuer)

    errors.add(:issuer, :invalid_issuer, message: "is not valid")
  end

  private def validate_azp_authorized_for_aud
    azp_app = authorized_party
    aud_app = audience

    return if azp_app.blank?

    unless aud_app.is_a?(ClientApplication)
      errors.add(:audience, :invalid_audience, message: "must be a valid application when azp is present")
      return
    end

    return if aud_app.obo_authorizations.exists?(azp_app.id)

    errors.add(:authorized_party, :not_authorized,
               message: "is not authorized to request tokens for audience #{aud_app.id}")
  end

  # ============================================================================
  # URL Helpers
  # ============================================================================

  private def base_url
    ENV.fetch("APP_URL", "https://xivauth.net")
  end

  private def application_url_for(id)
    "#{base_url}/applications/#{id}"
  end

  # ============================================================================
  # Utility Methods
  # ============================================================================

  def to_s
    token
  end

  def inspect
    "#<AttestationJwt signed=#{signed?} kid=#{header['kid'].inspect}>"
  end
end
