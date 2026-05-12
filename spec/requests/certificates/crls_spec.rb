require "rails_helper"

RSpec.describe "Certificates::CrlsController" do
  let(:ca) { FactoryBot.create(:pki_certificate_authority) }

  xdescribe "GET /certificates/crls/:slug" do
    it "returns DER with correct content type" do
      get crl_path(ca.slug)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pkix-crl")
    end

    it "returns a valid (empty) CRL signed by the CA" do
      get crl_path(ca.slug)

      crl = OpenSSL::X509::CRL.new(response.body)
      ca_cert = OpenSSL::X509::Certificate.new(ca.certificate_pem)
      expect(crl.verify(ca_cert.public_key)).to be true
      expect(crl.revoked).to be_empty
    end

    it "returns 404 for an unknown slug" do
      get crl_path("nonexistent-ca")
      expect(response).to have_http_status(:not_found)
    end
  end
end
