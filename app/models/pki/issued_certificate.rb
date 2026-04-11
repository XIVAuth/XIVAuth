class PKI::IssuedCertificate < ApplicationRecord
  extend AttributeHelper

  self.table_name = "pki_issued_certificates"

  # NOTE: Do NOT add dependent: destroy to inbound records for this table! We need to retain an audit log
  # of issued certificates for OCSP and operational purposes.

  belongs_to :certificate_authority, class_name: "PKI::CertificateAuthority"
  belongs_to :subject, polymorphic: true

  belongs_to :requesting_application, class_name: "ClientApplication",
             foreign_key: :requesting_application_id, optional: true

  # Revocation reasons that users are allowed to select to cancel their own certs.
  # All other revocations are system-reserved.
  USER_REVOCATION_REASONS = %w[
    unspecified
    key_compromise
    superseded
    cessation_of_operation
  ].freeze

  enum :revocation_reason, {
    unspecified: "unspecified",
    key_compromise: "key_compromise",
    ca_compromise: "ca_compromise",
    affiliation_changed: "affiliation_changed",
    superseded: "superseded",
    cessation_of_operation: "cessation_of_operation",
    certificate_hold: "certificate_hold",
    privilege_withdrawn: "privilege_withdrawn",
    aa_compromise: "aa_compromise"
  }, prefix: :revocation

  validates :certificate_pem, presence: true
  validates :certificate_type, presence: true,
            inclusion: { in: -> { PKI::IssuancePolicy::REGISTRY.keys }, message: "is not a known certificate type" }
  validates :issued_at, :expires_at, presence: true
  validates :public_key_info, presence: true
  validates :certificate_fingerprint, :public_key_fingerprint, presence: true
  validates :certificate_fingerprint, uniqueness: true  # generally validated by service, but catch here.

  protected attr_ar_setter :issued_at, :expires_at, :public_key_info, :certificate_fingerprint, :public_key_fingerprint

  # Override the certificate_pem setter to immediately derive attributes from the certificate
  def certificate_pem=(pem)
    super(pem)
    derive_certificate_attributes if pem.present?
  end
  
  def key_type
    public_key_info["type"]
  end

  def key_bits
    public_key_info["bits"]
  end

  def key_curve
    public_key_info["curve"]
  end

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :expired, -> { where(revoked_at: nil).where("expires_at <= ?", Time.current) }

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    !revoked? && expires_at <= Time.current
  end

  def revoke!(reason: "unspecified")
    return if revoked? # we can't re-revoke a certificate

    update!(revoked_at: Time.current, revocation_reason: reason)
  end

  def as_ca_gem_certificate
    @gem_cert ||= CertificateAuthority::Certificate.from_x509_cert(certificate_pem)
  end

  def as_openssl_certificate
    @openssl_cert ||= OpenSSL::X509::Certificate.new(certificate_pem)
  end

  def serial
    self.class.uuid_to_serial(id)
  end

  def self.find_by_serial(serial_integer)
    find_by(id: serial_to_uuid(serial_integer))
  end

  # Converts a UUID string to its integer serial representation.
  def self.uuid_to_serial(uuid)
    uuid.delete("-").to_i(16)
  end

  # Converts an integer serial back to a UUID string.
  def self.serial_to_uuid(serial)
    hex = serial.to_i.to_s(16).rjust(32, "0")
    [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
  end

  private

  # Derives and assigns certificate attributes from the PEM certificate.
  # Called automatically when certificate_pem is assigned via the certificate_pem= setter.
  def derive_certificate_attributes
    x509_cert = as_openssl_certificate

    cert_der = x509_cert.to_der
    public_key = x509_cert.public_key

    self.issued_at = x509_cert.not_before
    self.expires_at = x509_cert.not_after

    self.public_key_info = build_public_key_info(public_key)

    self.certificate_fingerprint = "sha256:#{OpenSSL::Digest::SHA256.hexdigest(cert_der)}"
    self.public_key_fingerprint = calculate_public_key_fingerprint(public_key)
  end

  def build_public_key_info(public_key)
    case public_key
    when OpenSSL::PKey::RSA
      { "type" => "RSA", "bits" => public_key.n.num_bits }
    when OpenSSL::PKey::EC
      { "type" => "EC", "curve" => public_key.group.curve_name, "bits" => public_key.group.degree }
    else
      { "type" => public_key.class.name }
    end
  end

  def calculate_public_key_fingerprint(public_key)
    spki_der = public_key.to_der
    "sha256:#{OpenSSL::Digest::SHA256.hexdigest(spki_der)}"
  end
end
