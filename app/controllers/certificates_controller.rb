class CertificatesController < ApplicationController
  layout "chroma/page"

  before_action :set_certificate, only: %i[show revoke destroy]
  skip_before_action :authenticate_user!, only: %i[why]

  def index
    @certificates = accessible_certificates.includes(subject: :character,
                                                     requesting_application: {}).order(issued_at: :desc)
  end

  def show
    respond_to do |format|
      format.html
      format.pem do
        send_data @certificate.certificate_pem,
                  type: "application/x-pem-file", disposition: "attachment",
                  filename: "#{@certificate.id}.pem"
      end
      format.der do
        send_data OpenSSL::X509::Certificate.new(@certificate.certificate_pem).to_der,
                  type: "application/pkix-cert", disposition: "attachment",
                  filename: "#{@certificate.id}.der"
      end
    end
  end

  def revoke
    authorize! :revoke, @certificate

    # If no form params, the user just clicked the button - show the modal.
    render and return if params[:revocation_reason].nil?

    reason = params[:revocation_reason].presence || "unspecified"
    unless PKI::IssuedCertificate::USER_REVOCATION_REASONS.include?(reason)
      return redirect_to certificate_path(@certificate), alert: "Invalid revocation reason."
    end

    @certificate.revoke!(reason: reason)
    redirect_to certificates_path, notice: "Certificate revoked."
  rescue ActiveRecord::RecordInvalid
    redirect_to certificate_path(@certificate), alert: "Could not revoke certificate."
  end

  def destroy
    authorize! :revoke, @certificate

    if @certificate.destroy
      redirect_to certificates_path, notice: "Certificate deleted."
    else
      redirect_to certificate_path(@certificate), alert: "Could not delete certificate."
    end
  end

  def why
    respond_to do |format|
      format.html { render layout: "chroma/container" }
    end
  end

  private def set_certificate
    @certificate = PKI::IssuedCertificate.find(params.expect(:id))
    authorize! :read, @certificate
  end

  private def accessible_certificates
    user_cert_ids = PKI::IssuedCertificate.where(subject_type: "User", subject_id: current_user.id)
    cr_ids = current_user.character_registrations.verified.select(:id)
    char_cert_ids = PKI::IssuedCertificate.where(subject_type: "CharacterRegistration", subject_id: cr_ids)

    PKI::IssuedCertificate.where(id: user_cert_ids).or(PKI::IssuedCertificate.where(id: char_cert_ids))
  end
end
