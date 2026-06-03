class Certificates::RequestsController < ApplicationController
  layout "chroma/page"

  before_action :check_issuance_enabled
  before_action :load_verified_characters

  def new
    prefill = params[:certificate_request]&.permit(:certificate_type).to_h
    @request = PKI::CertificateRequest.new(prefill)
  end

  def create
    @request = PKI::CertificateRequest.new(
      certificate_type: params.dig(:certificate_request, :certificate_type).to_s,
      csr_pem: params.dig(:certificate_request, :csr_file)&.read,
      subject: resolve_subject
    )

    unless @request.valid?
      render_error
      return
    end

    service = PKI::CertificateIssuanceService.new(
      subject: @request.subject,
      certificate_type: @request.certificate_type
    )
    result = service.issue!(csr_pem: @request.csr_pem)

    if result.is_a?(PKI::IssuedCertificate)
      redirect_to certificate_path(result), notice: "Certificate issued successfully."
    else
      result.errors.each { |e| @request.errors.add(:base, e.full_message) }
      render_error
    end
  rescue PKI::CertificateIssuanceService::IssuanceError => e
    @request.errors.add(:base, e.message)
    render_error
  end

  private

  def resolve_subject
    case params.dig(:certificate_request, :certificate_type).to_s
    when "user_identification"
      current_user
    when "character_identification"
      subject_id = params.dig(:certificate_request, :subject_id)
      @verified_characters.find_by(id: subject_id)
    end
  end

  def render_error
    respond_to do |format|
      format.turbo_stream do
        render status: :unprocessable_content,
               turbo_stream: turbo_stream.update("certificate_request_form",
                                                 partial: "certificates/requests/form",
                                                 locals: { cert_request: @request })
      end
      format.html { render :new, status: :unprocessable_content }
    end
  end

  def load_verified_characters
    @verified_characters = current_user.character_registrations.verified.includes(:character)
  end

  def check_issuance_enabled
    return if Flipper.enabled?(:certificate_management, current_user)

    redirect_to certificates_path, alert: "Certificate issuance is not currently available."
  end
end
