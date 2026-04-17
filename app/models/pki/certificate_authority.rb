class PKI::CertificateAuthority < ApplicationRecord
  extend AttributeHelper

  class NoCertificateAuthorityError < StandardError; end

  self.table_name = "pki_certificate_authorities"

  encrypts :private_key

  has_many :issued_certificates, foreign_key: :certificate_authority_id,
           class_name: "PKI::IssuedCertificate"

  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: "must be lowercase alphanumeric and hyphens only" }
  validates :certificate_fingerprint, uniqueness: true

  # Block changing slug - this is encoded in cert AIA data, so we can't break it.
  validate :slug_immutable_after_issuance, on: :update

  validates :certificate_pem, presence: true
  validates :private_key, presence: true
  validate :validate_certificate_is_ca, if: :certificate_pem_changed?
  validate :validate_private_key_matches_certificate, if: :certificate_pem_changed?

  protected attr_ar_setter :certificate_fingerprint, :public_key_fingerprint, :expires_at

  enum :revocation_reason, {
    unspecified:            "unspecified",
    key_compromise:         "key_compromise",
    ca_compromise:          "ca_compromise",
    affiliation_changed:    "affiliation_changed",
    superseded:             "superseded",
    cessation_of_operation: "cessation_of_operation",
    certificate_hold:       "certificate_hold",
    privilege_withdrawn:    "privilege_withdrawn",
    aa_compromise:          "aa_compromise"
  }, prefix: :revocation

  scope :active,      -> { where(active: true, revoked_at: nil) }
  scope :inactive,    -> { where(active: false) }
  scope :not_revoked, -> { where(revoked_at: nil) }

  scope :for_certificate_type, ->(type) {
    where("? = ANY(allowed_certificate_types)", type)
  }

  # Return the newest active CA for a specific certificate type.
  # @param certificate_type [String] e.g. "user_identification", "character_identification"
  def self.current_for(certificate_type:)
    active.for_certificate_type(certificate_type).order(created_at: :desc).first!
  rescue ActiveRecord::RecordNotFound
    raise NoCertificateAuthorityError, "No active CA certificate for certificate type #{certificate_type}"
  end

  def certificate_pem=(pem)
    super pem
    derive_certificate_metadata if pem.present?
  end

  def revoked? = revoked_at.present?

  # Revoke this CA. Sets revoked_at and deactivates.
  # NOTE: This does *not* revoke child certs - that decision is left to the developer performing this operation,
  # as we cannot decide what certs are eligible for revocation.
  def revoke!(reason: "unspecified")
    return if revoked?
    update!(revoked_at: Time.current, revocation_reason: reason, active: false)
  end

  # Convert to a CertificateAuthority::Certificate for use in signing.
  def as_ca_gem_issuer
    ca = CertificateAuthority::Certificate.from_x509_cert(certificate_pem)
    key_mat = CertificateAuthority::MemoryKeyMaterial.new
    key_mat.private_key = OpenSSL::PKey.read(private_key)
    ca.key_material = key_mat

    ca
  end

  def as_ca_gem_certificate
    @ca_gem_cert ||= CertificateAuthority::Certificate.from_x509_cert(certificate_pem)
  end

  def as_openssl_certificate
    return nil if certificate_pem.blank?
    @openssl_cert ||= OpenSSL::X509::Certificate.new(certificate_pem)
  end

  def as_openssl_pkey
    return nil if private_key.blank?
    OpenSSL::PKey.read(private_key)
  end

  private def derive_certificate_metadata
    cert = as_openssl_certificate
    return if cert.nil?

    self.certificate_fingerprint = "sha256:#{OpenSSL::Digest::SHA256.hexdigest(cert.to_der)}"
    self.public_key_fingerprint  = "sha256:#{OpenSSL::Digest::SHA256.hexdigest(cert.public_key.to_der)}"
    self.expires_at = cert.not_after
  rescue OpenSSL::X509::CertificateError => e
    errors.add(:certificate_pem, "is not a valid X.509 certificate: #{e.message}")
  end

  # Check against RFC 5280 §4.2.1.9 (basicConstraints: CA) and §4.2.1.3 (keyUsage: keyCertSign)
  private def validate_certificate_is_ca
    return if certificate_pem.blank?

    begin
      cert = OpenSSL::X509::Certificate.new(certificate_pem)
    rescue OpenSSL::X509::CertificateError => e
      errors.add(:certificate_pem, "is not a valid X.509 certificate: #{e.message}")
      return
    end

    bc = cert.extensions.find { |e| e.oid == "basicConstraints" }
    if bc.nil? || !bc.value.include?("CA:TRUE")
      errors.add(:certificate_pem, "must have basicConstraints CA:TRUE")
    end

    ku = cert.extensions.find { |e| e.oid == "keyUsage" }
    if ku.nil? || !ku.value.include?("Certificate Sign")
      errors.add(:certificate_pem, "must have keyUsage keyCertSign")
    end
  end

  private def validate_private_key_matches_certificate
    # skip validation if there's already something wrong with the certificate
    return if errors[:certificate_pem].present?

    cert = as_openssl_certificate
    return if cert.nil?

    return if private_key.blank?

    begin
      key = OpenSSL::PKey.read(private_key)
    rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError => e
      errors.add(:private_key, "could not be read: #{e.message}")
      return
    end

    unless cert.check_private_key(key)
      errors.add(:private_key, "does not match certificate public key")
    end
  end

  private def slug_immutable_after_issuance
    return unless will_save_change_to_slug? && issued_certificates.exists?
    errors.add(:slug, "cannot be changed after certificates have been issued")
  end
end
