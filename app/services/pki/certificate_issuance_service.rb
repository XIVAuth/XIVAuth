class PKI::CertificateIssuanceService
  class IssuanceError < StandardError; end

  # @param subject [User, CharacterRegistration, Team]
  # @param certificate_type [String] e.g. "user_identification", "character_identification", "code_signing"
  def initialize(subject:, certificate_type:)
    @subject = subject
    @certificate_type = certificate_type
  end

  # Issues a certificate from a CSR PEM string.
  #
  # @param csr_pem [String] PEM-encoded PKCS#10 CSR
  # @param requesting_application [ClientApplication, nil]
  # @param certificate_authority [PKI::CertificateAuthority, nil] defaults to .current_for
  # @return [PKI::IssuedCertificate] on success (persisted)
  # @return [PKI::IssuancePolicy::Base] with errors when policy.valid? == false
  # @raise [IssuanceError] on signing or persistence failure
  def issue!(csr_pem:, requesting_application: nil, certificate_authority: nil)
    csr = parse_csr!(csr_pem)
    public_key = csr.public_key

    ca_record = certificate_authority || PKI::CertificateAuthority.current_for(certificate_type: @certificate_type)

    # Build and validate policy. On failure, return the policy so the caller
    # can render policy.errors as 422. No signing or persistence occurs.
    policy = PKI::IssuancePolicy.for(
      certificate_type: @certificate_type,
      subject: @subject,
      public_key: public_key,
      certificate_authority: ca_record,
      requesting_application: requesting_application
    )
    return policy unless policy.valid?

    # Ask the policy to build the configured (unsigned) leaf certificate.
    # Policy owns all content decisions: CN, SANs, AIA, CDP, validity, and serial.
    leaf = policy.build_leaf

    # Sign outside of the builder, as the service needs responsibility.
    begin
      leaf.sign!(policy.signing_profile)
    rescue StandardError => e
      raise IssuanceError, "Certificate signing failed: #{e.message}"
    end

    cert_pem = leaf.to_pem

    begin
      PKI::IssuedCertificate.create!(
        id:                     policy.cert_uuid,
        certificate_authority:  ca_record,
        subject:                @subject,
        certificate_type:       @certificate_type,
        certificate_pem:        cert_pem,
        issuance_context:       policy.issuance_context,
        requesting_application: requesting_application
      )
    rescue ActiveRecord::RecordInvalid => e
      raise IssuanceError, "Certificate persistence failed: #{e.message}"
    end
  end

  private def parse_csr!(csr_pem)
    csr = OpenSSL::X509::Request.new(csr_pem)
    raise IssuanceError, "CSR self-signature verification failed" unless csr.verify(csr.public_key)

    csr
  rescue OpenSSL::X509::RequestError => e
    raise IssuanceError, "Invalid CSR: #{e.message}"
  end
end
