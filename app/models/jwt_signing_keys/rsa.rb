class JwtSigningKeys::RSA < JwtSigningKey
  after_initialize :generate_keypair, if: -> { new_record? && self[:private_key].blank? }
  validates :public_key, presence: true
  validates :size, numericality: { greater_than_or_equal_to: 2048 }

  validate :validate_public_key_consistent, if: :keys_changed?

  # @return [OpenSSL::PKey::RSA] A private RSA key.
  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(self[:private_key])
  end

  # @param [OpenSSL::PKey::RSA] key The RSA private key to store.
  def private_key=(key)
    self[:private_key] = key.private_to_pem
    self[:public_key] = key.public_to_pem

    key_params[:size] = key.public_key.n.num_bits

    # reset key cache
    @private_key = nil
    @public_key = nil
  end

  # @return [OpenSSL::PKey::RSA] A public RSA key.
  def public_key
    return @public_key if @public_key.present?

    if self[:public_key].present?
      @public_key = OpenSSL::PKey::RSA.new(self[:public_key])
    elsif private_key.present?
      logger.warn "Public key not saved for RSA key #{id}, deriving from private key."

      derived_key = private_key.public_key
      self[:public_key] = derived_key.to_pem
      @public_key = derived_key
    end
  end

  def generate_keypair(size = nil)
    size ||= key_params[:size] || 4096
    self.private_key = OpenSSL::PKey::RSA.generate(size)
  end

  def size=(size)
    return if self[:private_key].present?

    key_params[:size] = size
  end

  def size
    key_params[:size] || public_key.n.num_bits
  end

  def supported_algorithms
    # NOTE: It's not the greatest idea to reuse keys for all these algorithms,
    # but there shouldn't be any inherent cryptographic flaw in doing so. The
    # differences ultimately come down to hashing algorithm and padding, which
    # don't care about the key material. The end user ultimately decides which
    # algorithm they want, so they're making the security choice based on their
    # needs.

    # TODO: Figure out some way to read this from JWT again.
    %w[RS256 RS384 RS512 PS256 PS384 PS512]
  end

  private def validate_public_key_consistent
    return if public_key.blank? && private_key.blank?

    sig_data = "CRYPTO_VALIDATION_OPERATION"
    digest = OpenSSL::Digest.new("SHA256")
    signature = private_key.sign(digest, sig_data)

    return if public_key.verify(digest, signature, sig_data)

    errors.add(:public_key, "must be consistent with the private key")
  end
end
