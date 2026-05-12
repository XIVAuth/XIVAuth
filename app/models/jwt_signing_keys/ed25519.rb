class JwtSigningKeys::Ed25519 < JwtSigningKey
  after_initialize :generate_keypair, if: -> { new_record? && self[:private_key].blank? }
  validates :public_key, presence: true

  validate :validate_public_key_consistent, if: :keys_changed?

  # @return [Ed25519::SigningKey]
  def private_key
    @private_key ||= ::Ed25519::SigningKey.new(
      OpenSSL::PKey.read(self[:private_key]).raw_private_key
    )
  end

  # @param [Ed25519::SigningKey] key
  def private_key=(key)
    if key.is_a?(::Ed25519::SigningKey)
      encoded_key = OpenSSL::PKey.new_raw_private_key("Ed25519", key.to_bytes)

      self[:private_key] = encoded_key.private_to_pem
      self[:public_key] = encoded_key.public_to_pem
    elsif key.is_a?(OpenSSL::PKey::PKey)
      self[:private_key] = key.private_to_pem
      self[:public_key] = key.public_to_pem
    end

    # Clear caches to force fresh reads from the newly set values
    @private_key = nil
    @public_key = nil
  end

  # @return [Ed25519::VerifyKey]
  def public_key
    return @public_key if @public_key.present?

    if self[:public_key].present?
      @public_key = ::Ed25519::VerifyKey.new(
        OpenSSL::PKey.read(self[:public_key]).raw_public_key
      )
    elsif private_key.present?
      logger.warn "Public key not saved for Ed25519 key #{id}, deriving from private key."

      derived_key = private_key.verify_key
      self[:public_key] = OpenSSL::PKey
                          .new_raw_public_key("Ed25519", derived_key.to_bytes)
                          .public_to_pem

      @public_key = derived_key
    end
  end

  def generate_keypair
    self.private_key = ::Ed25519::SigningKey.generate
  end

  def supported_algorithms
    %w[EdDSA Ed25519]
  end

  private def validate_public_key_consistent
    return if public_key.blank? && private_key.blank?

    sig_data = "CRYPTO_VALIDATION_OPERATION"
    signature = private_key.sign(sig_data)

    begin
      public_key.verify(signature, sig_data)
    rescue ::Ed25519::VerifyError
      errors.add(:public_key, "must be consistent with the private key")
    end
  end
end
