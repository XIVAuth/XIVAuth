class Certificates::OcspController < ActionController::Base
  OCSP_REASON_CODES = {
    "unspecified" => OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED,
    "key_compromise" => OpenSSL::OCSP::REVOKED_STATUS_KEYCOMPROMISE,
    "ca_compromise" => OpenSSL::OCSP::REVOKED_STATUS_CACOMPROMISE,
    "affiliation_changed" => OpenSSL::OCSP::REVOKED_STATUS_AFFILIATIONCHANGED,
    "superseded" => OpenSSL::OCSP::REVOKED_STATUS_SUPERSEDED,
    "cessation_of_operation" => OpenSSL::OCSP::REVOKED_STATUS_CESSATIONOFOPERATION,
    "certificate_hold" => OpenSSL::OCSP::REVOKED_STATUS_CERTIFICATEHOLD,
    "privilege_withdrawn" => OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, # not in OpenSSL gem yet
    "aa_compromise" => OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, # not in OpenSSL gem yet
  }.freeze

  rate_limit to: 5, within: 1.minute
  skip_before_action :verify_authenticity_token

  def respond
    handle_ocsp_request(request.body.read)
  end

  def respond_get
    encoded = params[:encoded_request]
    # RFC 6960 §A.1 uses standard base64 that is then URL-encoded in the path.
    # Rails already URL-decodes the path segment, so we just need to base64-decode.
    der = Base64.decode64(encoded)
    handle_ocsp_request(der)
  rescue ArgumentError
    send_data OpenSSL::OCSP::Response.create(
      OpenSSL::OCSP::RESPONSE_STATUS_MALFORMEDREQUEST, nil
    ).to_der,
              type: "application/ocsp-response"
  end

  private

  def handle_ocsp_request(der)
    ocsp_reader = CertificateAuthority::OCSPRequestReader.from_der(der)

    begin
      serials = Array(ocsp_reader.serial_numbers)
    rescue NoMethodError
      serials = []
    end

    ca_records = PKI::CertificateAuthority.where(
      id: PKI::IssuedCertificate.where(serial: serials.map(&:to_i))
                                .select(:certificate_authority_id)
    ).distinct

    if ca_records.empty?
      response.set_header("X-OCSP-Error", "no serial numbers were recognized: could not determine issuing CA")
      return send_data OpenSSL::OCSP::Response.create(
        OpenSSL::OCSP::RESPONSE_STATUS_UNAUTHORIZED, nil
      ).to_der, type: "application/ocsp-response"
    end

    if ca_records.size > 1
      response.set_header("X-OCSP-Error", "certificates from multiple CAs were requested")
      return send_data OpenSSL::OCSP::Response.create(
        OpenSSL::OCSP::RESPONSE_STATUS_MALFORMEDREQUEST, nil
      ).to_der, type: "application/ocsp-response"
    end

    issuing_ca_record = ca_records.first

    builder = CertificateAuthority::OCSPResponseBuilder.from_request_reader(ocsp_reader)
    builder.parent = issuing_ca_record.as_ca_gem_issuer

    # Gem uses this lambda to get cert status per serial.
    # FIXME: certificate_authority gem doesn't support revocation time, so we can't set that yet.
    builder.verification_mechanism = ->(serial_bn) {
      cert = PKI::IssuedCertificate.find_by_serial(serial_bn.to_i)
      if cert.nil?
        [OpenSSL::OCSP::V_CERTSTATUS_UNKNOWN, 0]
      elsif cert.revoked?
        reason_code = OCSP_REASON_CODES.fetch(cert.revocation_reason, OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED)
        [CertificateAuthority::OCSPResponseBuilder::REVOKED, reason_code]
      else
        [CertificateAuthority::OCSPResponseBuilder::GOOD,
         CertificateAuthority::OCSPResponseBuilder::NO_REASON]
      end
    }

    send_data builder.build_response.to_der, type: "application/ocsp-response"
  end
end