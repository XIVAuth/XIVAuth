class Certificates::CrlsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    ca_record = PKI::CertificateAuthority.find_by(slug: params.expect(:slug))
    if ca_record.nil?
      head :not_found
      return
    end

    revoked = ca_record.issued_certificates
                       .where.not(revocation_reason: nil)
                       .where(revoked_at: ..Time.current)
                       .where(expires_at: 3.months.ago..)

    crl = CertificateAuthority::CertificateRevocationList.new
    crl.parent = ca_record.as_ca_gem_issuer
    crl.next_update = 24 * 60 * 60

    revoked.each do |issued_cert|
      serial = CertificateAuthority::SerialNumber.new
      serial.number = issued_cert.serial
      serial.revoke!(issued_cert.revoked_at)
      crl << serial
    end

    crl.sign!

    send_data crl.crl_body.to_der, type: "application/pkix-crl", disposition: "inline"
  end
end
