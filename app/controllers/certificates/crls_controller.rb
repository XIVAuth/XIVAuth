class Certificates::CrlsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    head :service_unavailable and return

    ca_record = PKI::CertificateAuthority.find_by!(slug: params.expect(:slug))

    # TODO: Full CRL population with revoked entries is deferred.
    # I don't want to generate this on the fly, so we're just... not going to do that yet.
    # For now, always return an empty (but valid) CRL.
    revoked = []

    crl = CertificateAuthority::CertificateRevocationList.new
    crl.parent = ca_record.as_ca_gem_issuer
    crl.next_update = 24 * 60 * 60

    revoked.each do |issued_cert|
      serial = CertificateAuthority::SerialNumber.new
      serial.number = issued_cert.id.delete("-").to_i(16)
      serial.revoke!(issued_cert.revoked_at)
      crl << serial
    end

    crl.sign!

    send_data crl.crl_body.to_der, type: "application/pkix-crl", disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
