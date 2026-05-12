class JwtSigningKeys::ECDSA < JwtSigningKey
  after_initialize :generate_keypair, if: -> { new_record? && self[:private_key].blank? }
  validates :public_key, presence: true
  validates :curve, inclusion: ::JWT::JWA::Ecdsa::NAMED_CURVES.keys

  validate :validate_public_key_consistent, if: :keys_changed?

  # @return [OpenSSL::PKey::EC] A private RSA key.
  def private_key
    @private_key ||= OpenSSL::PKey::EC.new self[:private_key]
  end

  # @param [OpenSSL::PKey::EC] key The EC private key to store.
  def private_key=(key)
    self[:private_key] = key.to_pem
    self[:public_key] = key.public_to_pem

    @private_key = key
    @public_key = nil # needs to be recalculated from the PEM, can be deferred.

    key_params[:curve] = key.public_key&.group&.curve_name
  end

  # @return [OpenSSL::PKey::EC] A public EC key.
  def public_key
    return @public_key if @public_key.present?

    if self[:public_key].present?
      @public_key = OpenSSL::PKey::EC.new(self[:public_key])
    elsif private_key.present?
      logger.warn "Public key not saved for EC key #{id}, deriving from private key."

      derived_key = OpenSSL::PKey::EC.new(private_key.public_to_pem)
      self[:public_key] = derived_key.to_pem
      @public_key = derived_key
    end
  end

  def generate_keypair(curve = nil)
    curve ||= key_params[:curve] || "prime256v1"
    self.private_key = OpenSSL::PKey::EC.generate(curve)
  end

  def curve
    key_params[:curve] || public_key.group&.curve_name
  end

  def curve=(curve)
    return if self[:private_key].present?

    key_params[:curve] = curve
  end

  def supported_algorithms
    [::JWT::JWA::Ecdsa::NAMED_CURVES[curve][:algorithm]]
  end

  private def validate_public_key_consistent
    sig_data = "CRYPTO_VALIDATION_OPERATION"
    digest = OpenSSL::Digest.new("SHA256")
    signature = private_key.sign(digest, sig_data)

    return if public_key.verify(digest, signature, sig_data)

    errors.add(:public_key, "must be consistent with the private key")
  end

  def self.preferred_key_for_algorithm(algorithm_name)
    curves = ::JWT::JWA::Ecdsa::NAMED_CURVES.filter { |_, c| c[:algorithm] == algorithm_name }

    active.where("key_params->>'curve' IN (?)", curves.keys).first
  end
end
