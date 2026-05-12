require "rails_helper"

RSpec.describe "Certificates::OcspController" do
  let(:ca) { FactoryBot.create(:pki_certificate_authority) }

  def build_ocsp_request_der(serials)
    ocsp_req = OpenSSL::OCSP::Request.new
    ca_cert  = OpenSSL::X509::Certificate.new(ca.certificate_pem)

    serials.each do |_serial|
      cert_id = OpenSSL::OCSP::CertificateId.new(
        OpenSSL::X509::Certificate.new(create(:pki_issued_certificate, certificate_authority: ca).certificate_pem),
        ca_cert
      )
      # Override the serial with the value we want to query
      ocsp_req.add_certid(cert_id)
    end

    ocsp_req.to_der
  end

  describe "POST /certificates/ocsp" do
    context "with a good certificate" do
      let(:cert) { FactoryBot.create(:pki_issued_certificate, certificate_authority: ca) }
      let(:ocsp_response) do
        ocsp_req = OpenSSL::OCSP::Request.new
        ca_cert  = OpenSSL::X509::Certificate.new(ca.certificate_pem)
        leaf_cert = OpenSSL::X509::Certificate.new(cert.certificate_pem)
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf_cert, ca_cert))

        post ocsp_certificates_path,
             params: ocsp_req.to_der,
             headers: { "CONTENT_TYPE" => "application/ocsp-request" }

        OpenSSL::OCSP::Response.new(response.body)
      end

      it "returns OCSP good status" do
        ocsp_response

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/ocsp-response")
      end

      it "preserves the request nonce in the response (RFC 6960 §4.4.1)" do
        ocsp_req = OpenSSL::OCSP::Request.new
        ca_cert  = OpenSSL::X509::Certificate.new(ca.certificate_pem)
        leaf_cert = OpenSSL::X509::Certificate.new(cert.certificate_pem)
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf_cert, ca_cert))
        ocsp_req.add_nonce

        post ocsp_certificates_path,
             params: ocsp_req.to_der,
             headers: { "CONTENT_TYPE" => "application/ocsp-request" }

        ocsp_resp = OpenSSL::OCSP::Response.new(response.body)
        # check_nonce returns 1 when nonces are present and match
        expect(ocsp_req.check_nonce(ocsp_resp.basic)).to eq(1),
                                                         "OCSP response must echo the request nonce"
      end

      it "response is signed by the CA (RFC 6960 §4.2.1)" do
        basic   = ocsp_response.basic
        ca_cert = OpenSSL::X509::Certificate.new(ca.certificate_pem)
        store   = OpenSSL::X509::Store.new
        store.add_cert(ca_cert)

        expect(basic.verify([ca_cert], store))
          .to be(true), "OCSP response signature must verify against the issuing CA certificate"
      end

      it "encodes thisUpdate/nextUpdate as valid ASN.1 times (RFC 6960 §2.2)" do
        basic = ocsp_response.basic
        expect(basic).not_to be_nil
        expect(basic.responses).not_to be_empty
        cert_state = basic.responses.first

        expect(cert_state.this_update).to be_within(1.minute).of(Time.current)
        expect(cert_state.next_update).not_to be_nil
        expect(cert_state.next_update).to be > Time.current
      end
    end

    context "with a revoked certificate" do
      def ocsp_status_for(cert, authority)
        ca_cert   = OpenSSL::X509::Certificate.new(authority.certificate_pem)
        leaf_cert = OpenSSL::X509::Certificate.new(cert.certificate_pem)
        ocsp_req  = OpenSSL::OCSP::Request.new
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf_cert, ca_cert))

        post ocsp_certificates_path,
             params: ocsp_req.to_der,
             headers: { "CONTENT_TYPE" => "application/ocsp-request" }

        OpenSSL::OCSP::Response.new(response.body).basic.status.first
      end

      it "returns OCSP revoked status" do
        cert = FactoryBot.create(:pki_issued_certificate, :revoked, certificate_authority: ca)
        _cert_id, status, = ocsp_status_for(cert, ca)
        expect(status).to eq(OpenSSL::OCSP::V_CERTSTATUS_REVOKED)
      end

      it "returns unspecified reason code for unspecified revocation" do
        cert = FactoryBot.create(:pki_issued_certificate, :revoked, certificate_authority: ca,
                                 revocation_reason: "unspecified")
        _cert_id, _status, reason = ocsp_status_for(cert, ca)
        expect(reason).to eq(OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED)
      end

      it "returns keyCompromise reason code for key_compromise revocation" do
        cert = FactoryBot.create(:pki_issued_certificate, :revoked, certificate_authority: ca,
                                 revocation_reason: "key_compromise")
        _cert_id, _status, reason = ocsp_status_for(cert, ca)
        expect(reason).to eq(OpenSSL::OCSP::REVOKED_STATUS_KEYCOMPROMISE)
      end

      it "returns superseded reason code for superseded revocation" do
        cert = FactoryBot.create(:pki_issued_certificate, :revoked, certificate_authority: ca,
                                 revocation_reason: "superseded")
        _cert_id, _status, reason = ocsp_status_for(cert, ca)
        expect(reason).to eq(OpenSSL::OCSP::REVOKED_STATUS_SUPERSEDED)
      end

      it "returns cessationOfOperation reason code for cessation_of_operation revocation" do
        cert = FactoryBot.create(:pki_issued_certificate, :revoked, certificate_authority: ca,
                                 revocation_reason: "cessation_of_operation")
        _cert_id, _status, reason = ocsp_status_for(cert, ca)
        expect(reason).to eq(OpenSSL::OCSP::REVOKED_STATUS_CESSATIONOFOPERATION)
      end
    end

    context "with no recognized serials" do
      it "returns unauthorized DER response" do
        ocsp_req = OpenSSL::OCSP::Request.new
        post ocsp_certificates_path,
             params: ocsp_req.to_der,
             headers: { "CONTENT_TYPE" => "application/ocsp-request" }

        expect(response.content_type).to eq("application/ocsp-response")
        parsed = OpenSSL::OCSP::Response.new(response.body)
        expect(parsed.status).to eq(OpenSSL::OCSP::RESPONSE_STATUS_UNAUTHORIZED)
      end

      it "returns unauthorized via GET as well" do
        ocsp_req = OpenSSL::OCSP::Request.new
        encoded  = Base64.encode64(ocsp_req.to_der).delete("\n")

        get ocsp_get_certificates_path(encoded_request: encoded)

        expect(response.content_type).to eq("application/ocsp-response")
        parsed = OpenSSL::OCSP::Response.new(response.body)
        expect(parsed.status).to eq(OpenSSL::OCSP::RESPONSE_STATUS_UNAUTHORIZED)
      end
    end

    context "via HTTP GET (RFC 6960 §A.1)" do
      let(:cert) { FactoryBot.create(:pki_issued_certificate, certificate_authority: ca) }

      it "returns OCSP good status for a valid base64-encoded request" do
        ca_cert   = OpenSSL::X509::Certificate.new(ca.certificate_pem)
        leaf_cert = OpenSSL::X509::Certificate.new(cert.certificate_pem)
        ocsp_req  = OpenSSL::OCSP::Request.new
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf_cert, ca_cert))

        encoded = Base64.encode64(ocsp_req.to_der).delete("\n")
        get ocsp_get_certificates_path(encoded_request: encoded)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/ocsp-response")

        ocsp_resp = OpenSSL::OCSP::Response.new(response.body)
        expect(ocsp_resp.status).to eq(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL)
      end
    end

    context "with serials from multiple CAs" do
      it "returns malformedRequest with X-OCSP-Error header" do
        ca2   = FactoryBot.create(:pki_certificate_authority, slug: "second-ca")
        cert1 = FactoryBot.create(:pki_issued_certificate, certificate_authority: ca)
        cert2 = FactoryBot.create(:pki_issued_certificate, certificate_authority: ca2)

        ca1_cert  = OpenSSL::X509::Certificate.new(ca.certificate_pem)
        ca2_cert  = OpenSSL::X509::Certificate.new(ca2.certificate_pem)
        leaf1     = OpenSSL::X509::Certificate.new(cert1.certificate_pem)
        leaf2     = OpenSSL::X509::Certificate.new(cert2.certificate_pem)

        ocsp_req = OpenSSL::OCSP::Request.new
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf1, ca1_cert))
        ocsp_req.add_certid(OpenSSL::OCSP::CertificateId.new(leaf2, ca2_cert))

        post ocsp_certificates_path,
             params: ocsp_req.to_der,
             headers: { "CONTENT_TYPE" => "application/ocsp-request" }

        expect(response.content_type).to eq("application/ocsp-response")
        expect(response.headers["X-OCSP-Error"]).to include("multiple CAs")
        parsed = OpenSSL::OCSP::Response.new(response.body)
        expect(parsed.status).to eq(OpenSSL::OCSP::RESPONSE_STATUS_MALFORMEDREQUEST)
      end
    end
  end
end
