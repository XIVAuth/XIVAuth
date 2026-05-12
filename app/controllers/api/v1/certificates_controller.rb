class Api::V1::CertificatesController < Api::V1::ApiController
  include Api::FiltersAuthorizedCharacters

  before_action :check_resource_owner_presence
  before_action :set_certificate, only: %i[show revoke]

  before_action(only: %i[index show]) do
    doorkeeper_authorize! "certificate", "certificate:all", "certificate:issue", "certificate:revoke",
                          "certificate:manage"
  end
  before_action(only: %i[request_cert]) { doorkeeper_authorize! "certificate:issue", "certificate:manage" }
  before_action(only: %i[revoke]) { doorkeeper_authorize! "certificate:revoke", "certificate:manage" }

  def index
    @certificates = accessible_certificates.includes(subject: :character,
                                                     requesting_application: { }).order(issued_at: :desc)
    render json: @certificates
  end

  def show
    render json: @certificate
  end

  # Params:
  #   csr_pem            [String]  PEM-encoded CSR (required)
  #   certificate_type   [String]  e.g. "user_identification", "character_identification" (required)
  #   subject_id         [String]  Subject UUID — required for character_identification, optional otherwise
  def request_cert
    certificate_type = params.require(:certificate_type).to_s

    # Validate certificate type exists
    policy_class = PKI::IssuancePolicy.registry[certificate_type]
    unless policy_class
      return render json: { error: "Unknown certificate_type '#{certificate_type}'" }, status: :bad_request
    end

    # Check that the application has permission to issue this certificate type
    unless can?(:issue, policy_class)
      return render json: { error: "Application is not authorized to issue '#{certificate_type}' certificates" },
                    status: :forbidden
    end

    subject = resolve_subject_for(certificate_type)
    return unless subject

    service = PKI::CertificateIssuanceService.new(subject: subject, certificate_type: certificate_type)
    result = service.issue!(
      csr_pem: read_csr_pem,
      requesting_application: requesting_application
    )

    if result.is_a?(PKI::IssuedCertificate)
      render json: {
        id: result.id,
        certificate: result.certificate_pem,
        fingerprint: result.public_key_fingerprint.sub(/^\w+:/, ""),
        ca_url: ca_cert_url(result.certificate_authority.slug)
      }, status: :created

      # certificate was successfully issued, enable the certificates view in the UI.
      current_user.profile.set_feature_enabled!(:certificate_management, true)
    else
      # result is an invalid policy - return its errors
      render json: { errors: result.errors.full_messages }, status: :unprocessable_content
    end
  rescue PKI::CertificateAuthority::NoCertificateAuthorityError => e
    render json: { error: e.message }, status: :service_unavailable
  rescue PKI::CertificateIssuanceService::IssuanceError => e
    render json: { error: e.message }, status: :unprocessable_content
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  end

  def revoke
    authorize! :revoke, @certificate

    # Check that the application has permission to revoke this certificate type
    policy_class = PKI::IssuancePolicy.registry[@certificate.certificate_type]
    unless can?(:revoke, policy_class)
      return render status: :forbidden, json: {
        error: "Application is not authorized to revoke '#{@certificate.certificate_type}' certificates"
      }
    end

    reason = params.require(:reason).to_s
    unless PKI::IssuedCertificate::USER_REVOCATION_REASONS.include?(reason)
      return render status: :bad_request, json: {
        error: "Invalid revocation reason."
      }
    end

    @certificate.revoke!(reason: reason)
    head :no_content
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  end

  private def set_certificate
    @certificate = accessible_certificates.find(params.expect(:id))
    authorize! :read, @certificate
  end

  # Resolve subject based on certificate_type. Each type has its own rules for how
  # the subject is determined and which scopes are required.
  private def resolve_subject_for(certificate_type)
    case certificate_type
    when "user_identification"
      resolve_user_subject
    when "character_identification"
      resolve_character_subject
    when "code_signing"
      resolve_code_signing_subject
    else
      render json: { error: "Subject resolution not supported for certificate type '#{certificate_type}'" },
             status: :bad_request
      nil
    end
  end

  # user_identification: always the current user; no subject params needed.
  private def resolve_user_subject
    unless user_scope_granted?
      render json: { error: "User scope required for certificate issuance" }, status: :forbidden
      return
    end

    current_user
  end

  # character_identification: requires subject_id (Lodestone ID of target character).
  private def resolve_character_subject
    unless character_scope_granted?
      render json: { error: "Character scope required for certificate issuance" }, status: :forbidden
      return
    end

    subject_id = params.require(:subject_id)

    authorized_character_registrations(only_verified: true)
      .joins(:character)
      .find_by!("character.lodestone_id": subject_id)
  end

  # code_signing: subject is the current user when no subject params are given,
  # or a specific entity identified by subject_type + subject_id.
  #   subject_type: "User" or "Team" (required when subject_id is present)
  #   subject_id:   UUID of the subject (required when subject_type is present)
  private def resolve_code_signing_subject
    unless user_scope_granted?
      render json: { error: "User scope required for certificate issuance" }, status: :forbidden
      return
    end

    subject_type = params[:subject_type]
    subject_id = params[:subject_id]

    # No subject params → default to current user
    return current_user if subject_type.blank? && subject_id.blank?

    # Both must be present if either is given
    if subject_type.blank? || subject_id.blank?
      render json: { error: "Both subject_type and subject_id are required for code_signing certificates" },
             status: :bad_request
      return
    end

    case subject_type
    when "User"
      unless subject_id == current_user.id
        render json: { error: "Cannot issue certificates for other users" }, status: :forbidden
        return
      end
      current_user
    when "Team"
      team = current_user.teams_by_membership_scope(:admins).find_by(id: subject_id)
      unless team
        render json: { error: "Team not found or insufficient permissions" }, status: :not_found
        return
      end
      team
    else
      render json: { error: "Invalid subject_type '#{subject_type}' for code_signing certificates" },
             status: :bad_request
      nil
    end
  end

  # Return a list of certificates accessible in the current context.
  #
  # Unless certificate:all or certificate:manage is passed, only the certificates issued to *this application* will
  # be visible.
  #
  # Additionally, to access a certificate, this context *must* be able to see the subject associated with the
  # certificate as well. This applies even for `certificate:manage`.
  private def accessible_certificates
    scope = PKI::IssuedCertificate.all

    scope = scope.where(requesting_application: requesting_application) unless certificate_all_scope_granted?

    conditions = []

    conditions << { subject_type: "User", subject_id: current_user.id } if user_scope_granted?

    if character_scope_granted?
      authorized_character_ids = authorized_character_registrations(only_verified: true).pluck(:id)
      unless authorized_character_ids.empty?
        conditions << {
          subject_type: "CharacterRegistration",
          subject_id: authorized_character_ids
        }
      end
    end

    return scope.none if conditions.empty?

    conditions.reduce(scope.none) { |combined, condition| combined.or(scope.where(condition)) }
  end

  private def certificate_all_scope_granted?
    doorkeeper_token.scopes.exists?("certificate:all") ||
      doorkeeper_token.scopes.exists?("certificate:manage")
  end

  private def user_scope_granted?
    doorkeeper_token.scopes.exists?("user") || doorkeeper_token.scopes.exists?("user:manage")
  end

  private def read_csr_pem
    param = params.require(:csr_pem)
    case param
    when ActionDispatch::Http::UploadedFile
      param.read
    when String
      param
    else
      raise ActionController::BadRequest, "csr_pem must be a PEM string or file upload"
    end
  end

  private def requesting_application
    doorkeeper_token.application&.application
  end
end
