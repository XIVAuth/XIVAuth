class PKI::CertificateRequest
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :certificate_type, :string
  attribute :csr_pem, :string

  attr_accessor :subject

  validates :subject, presence: true
  validates :certificate_type, inclusion: {in: ->(r) { PKI::IssuancePolicy.registry.keys }}
  validates :csr_pem, presence: {message: "Please upload a CSR file"}
  validate :csr_pem_parseable, if: -> { csr_pem.present? }
  validate :subject_valid_for_type, if: -> { certificate_type.present? && subject.present? }

  private

  def csr_pem_parseable
    OpenSSL::X509::Request.new(csr_pem)
  rescue OpenSSL::OpenSSLError, TypeError
    errors.add(:csr_pem, "is not a valid CSR")
  end

  def subject_valid_for_type
    policy_class = PKI::IssuancePolicy.registry[certificate_type]
    return unless policy_class

    unless policy_class.allowed_subject_types.any? { |klass| subject.is_a?(klass) }
      errors.add(:subject, :invalid)
      return
    end

    errors.add(:subject, "must be a verified character") if subject.is_a?(CharacterRegistration) && !subject.verified?
  end
end