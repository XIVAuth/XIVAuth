require "rails_helper"
require "support/without_detailed_exceptions"

RSpec.describe "Api::V1::CertificatesController", type: :request do
  before(:context) do
    @ca = FactoryBot.create(:pki_certificate_authority)
  end

  after(:context) do
    @ca&.destroy
  end

  let(:user) { FactoryBot.create(:user) }
  let(:oauth_client) { FactoryBot.create(:oauth_client) }
  let(:other_oauth_client) { FactoryBot.create(:oauth_client) }

  describe "GET /api/v1/certificates" do
    # List endpoint tests
    context "with user scope" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns user's certificates" do
        mine = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)
        other = FactoryBot.create(:pki_issued_certificate, certificate_authority: @ca,
                                  requesting_application: oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body.pluck("id")
        expect(ids).to include(mine.id)
        expect(ids).not_to include(other.id)
      end

      it "returns empty list without user scope" do
        FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                          requesting_application: oauth_client.application)
        token_without_user = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:all")

        get api_v1_certificates_path, headers: { "Authorization" => "Bearer #{token_without_user.token}" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_empty
      end
    end

    context "with character:all scope" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all character:all") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns all verified character certificates" do
        verified_char1 = FactoryBot.create(:verified_registration, user: user)
        verified_char2 = FactoryBot.create(:verified_registration, user: user)
        cert1 = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char1,
                                  certificate_authority: @ca, requesting_application: oauth_client.application)
        cert2 = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char2,
                                  certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body.pluck("id")
        expect(ids).to include(cert1.id, cert2.id)
      end

      it "does not return unverified character certificates" do
        unverified_char = FactoryBot.create(:character_registration, user: user)
        FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: unverified_char,
                          certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_empty
      end

      it "does not return other user's character certificates" do
        other_user = FactoryBot.create(:user)
        other_char = FactoryBot.create(:verified_registration, user: other_user)
        FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: other_char,
                          certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_empty
      end

      it "returns empty list without character scope" do
        verified_char = FactoryBot.create(:verified_registration, user: user)
        FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char,
                          certificate_authority: @ca, requesting_application: oauth_client.application)
        token_without_char = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:all")

        get api_v1_certificates_path, headers: { "Authorization" => "Bearer #{token_without_char.token}" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_empty
      end
    end

    context "with character scope and policy" do
      let(:allowed_char) { FactoryBot.create(:verified_registration, user: user) }
      let(:other_char) { FactoryBot.create(:verified_registration, user: user) }
      let(:policy) do
        OAuth::PermissiblePolicy.create.tap do |p|
          p.rules.create(resource: allowed_char, deny: false)
        end
      end
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all character", permissible_policy: policy) }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns only policy-allowed character certificates" do
        allowed_cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: allowed_char,
                                         certificate_authority: @ca, requesting_application: oauth_client.application)
        other_cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: other_char,
                                       certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body.pluck("id")
        expect(ids).to include(allowed_cert.id)
        expect(ids).not_to include(other_cert.id)
      end
    end

    context "with certificate:all scope" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns certificates from all applications" do
        cert1 = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                  requesting_application: oauth_client.application)
        cert2 = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                  requesting_application: other_oauth_client.application)

        get api_v1_certificates_path, headers: headers

        expect(response).to have_http_status(:ok)
        ids = response.parsed_body.pluck("id")
        expect(ids).to include(cert1.id, cert2.id)
      end
    end

    # Single certificate endpoint tests
    context "when accessing single certificates" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all user character:all") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns user certificate" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        get api_v1_certificate_path(cert), headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(cert.id)
      end

      it "returns character certificate" do
        verified_char = FactoryBot.create(:verified_registration, user: user)
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificate_path(cert), headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(cert.id)
      end

      it "returns 404 for other user's certificate" do
        other_user = FactoryBot.create(:user)
        cert = FactoryBot.create(:pki_issued_certificate, subject: other_user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for unverified character certificate" do
        unverified_char = FactoryBot.create(:character_registration, user: user)
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: unverified_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 without user scope" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)
        token_without_user = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:all")

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: { "Authorization" => "Bearer #{token_without_user.token}" }
        end

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 without character scope" do
        verified_char = FactoryBot.create(:verified_registration, user: user)
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)
        token_without_char = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:all")

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: { "Authorization" => "Bearer #{token_without_char.token}" }
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with policy restrictions" do
      let(:allowed_char) { FactoryBot.create(:verified_registration, user: user) }
      let(:denied_char) { FactoryBot.create(:verified_registration, user: user) }
      let(:policy) do
        OAuth::PermissiblePolicy.create.tap do |p|
          p.rules.create(resource: allowed_char, deny: false)
        end
      end
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:all character", permissible_policy: policy) }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "allows access to policy-allowed certificate" do
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: allowed_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)

        get api_v1_certificate_path(cert), headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(cert.id)
      end

      it "returns 404 for policy-denied certificate" do
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: denied_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    # Cross-application access control
    context "without certificate:all scope" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "blocks access to certificates issued to other applications" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: other_oauth_client.application)

        without_detailed_exceptions do
          get api_v1_certificate_path(cert), headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/certificates/request" do
    let(:csr_pem) { PkiSupport.generate_csr_pem }

    context "for user certificates" do
      context "with proper scopes" do
        let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue user") }
        let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

        it "issues a certificate for the authenticated user" do
          expect do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "user_identification", csr_pem: csr_pem },
                 headers: headers
          end.to change(PKI::IssuedCertificate, :count).by(1)

          expect(response).to have_http_status(:created)
        end

        it "returns 422 when the policy rejects the request" do
          weak_csr = PkiSupport.generate_csr_pem(key: OpenSSL::PKey::RSA.new(1024))

          post request_api_v1_certificates_path,
               params: { certificate_type: "user_identification", csr_pem: weak_csr },
               headers: headers

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["errors"]).to be_present
        end

        it "sets requesting_application from the doorkeeper token" do
          post request_api_v1_certificates_path,
               params: { certificate_type: "user_identification", csr_pem: csr_pem },
               headers: headers

          expect(response).to have_http_status(:created)
          cert = PKI::IssuedCertificate.find(response.parsed_body["id"])
          expect(cert.requesting_application).to eq(oauth_client.application)
        end

        it "embeds AIA and CRL URLs from default_url_options regardless of request Host header" do
          spoofed_headers = headers.merge("Host" => "evil.example.com")

          post request_api_v1_certificates_path,
               params: { certificate_type: "user_identification", csr_pem: csr_pem },
               headers: spoofed_headers

          expect(response).to have_http_status(:created)
          cert = OpenSSL::X509::Certificate.new(response.parsed_body["certificate"])

          url_extensions = cert.extensions.select { |e| %w[authorityInfoAccess crlDistributionPoints].include?(e.oid) }
          expect(url_extensions).not_to be_empty

          url_extensions.each do |ext|
            ext.value.scan(%r{https?://[^\s,]+}).each do |url|
              expect(url).to start_with("http://test.xivauth.net"),
                             "Expected #{ext.oid} URL #{url.inspect} to use default_url_options host"
            end
          end
        end
      end

      context "without user scope" do
        let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue") }
        let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

        it "returns 403 when user scope is missing" do
          post request_api_v1_certificates_path,
               params: { certificate_type: "user_identification", csr_pem: csr_pem },
               headers: headers

          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context "for character certificates" do
      let(:verified_char) { FactoryBot.create(:verified_registration, user: user) }

      context "with character:all scope" do
        let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue character:all") }
        let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

        it "issues a certificate for a verified character" do
          expect do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification",
                           subject_id: verified_char.character.lodestone_id, csr_pem: csr_pem },
                 headers: headers
          end.to change(PKI::IssuedCertificate, :count).by(1)

          expect(response).to have_http_status(:created)
        end

        it "returns 404 for unverified character" do
          unverified_char = FactoryBot.create(:character_registration, user: user)

          without_detailed_exceptions do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification", subject_id: unverified_char.id,
                           csr_pem: csr_pem },
                 headers: headers
          end

          expect(response).to have_http_status(:not_found)
        end

        it "returns 404 for other user's character" do
          other_user = FactoryBot.create(:user)
          other_char = FactoryBot.create(:verified_registration, user: other_user)

          without_detailed_exceptions do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification", subject_id: other_char.id, csr_pem: csr_pem },
                 headers: headers
          end

          expect(response).to have_http_status(:not_found)
        end
      end

      context "with character scope and permissible policy" do
        let(:allowed_char) { FactoryBot.create(:verified_registration, user: user) }
        let(:denied_char) { FactoryBot.create(:verified_registration, user: user) }
        let(:policy) do
          OAuth::PermissiblePolicy.create.tap do |p|
            p.rules.create(resource: allowed_char, deny: false)
          end
        end
        let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue character", permissible_policy: policy) }
        let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

        it "issues certificate for allowed character" do
          expect do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification",
                           subject_id: allowed_char.character.lodestone_id, csr_pem: csr_pem },
                 headers: headers
          end.to change(PKI::IssuedCertificate, :count).by(1)

          expect(response).to have_http_status(:created)
        end

        it "returns 404 for denied character" do
          without_detailed_exceptions do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification", subject_id: denied_char.id, csr_pem: csr_pem },
                 headers: headers
          end

          expect(response).to have_http_status(:not_found)
        end
      end

      context "without character scope" do
        let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue") }
        let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

        it "returns 403 when character scope is missing" do
          without_detailed_exceptions do
            post request_api_v1_certificates_path,
                 params: { certificate_type: "character_identification", subject_id: verified_char.id,
                           csr_pem: csr_pem },
                 headers: headers
          end

          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context "for entitlement-gated certificate types" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns 403 for code_signing certificates without entitlement" do
        post request_api_v1_certificates_path,
             params: { certificate_type: "code_signing", csr_pem: csr_pem },
             headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to include("not authorized to issue")
      end

      it "allows code_signing certificates with entitlement" do
        oauth_client.application.update!(entitlements: ["code_signing_certificates"])

        expect do
          post request_api_v1_certificates_path,
               params: { certificate_type: "code_signing", csr_pem: csr_pem },
               headers: headers
        end.to change(PKI::IssuedCertificate, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context "with invalid parameters" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns 400 for unknown certificate_type" do
        post request_api_v1_certificates_path,
             params: { certificate_type: "invalid", csr_pem: csr_pem },
             headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 400 when certificate_type is missing" do
        post request_api_v1_certificates_path,
             params: { csr_pem: csr_pem },
             headers: headers

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when no CA is available" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:issue user character:all") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      # HACK: around our before/after blocks, since these tests explicitly want no active CAs.
      around do |example|
        @ca.update_column(:active, false) # rubocop:disable Rails/SkipsModelValidations
        example.run
      ensure
        @ca.update_column(:active, true) # rubocop:disable Rails/SkipsModelValidations
      end

      it "returns 503 for user certificate type" do
        post request_api_v1_certificates_path,
             params: { certificate_type: "user_identification", csr_pem: csr_pem },
             headers: headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to include("No active CA certificate for certificate type")
      end

      it "returns 503 for character certificate type" do
        verified_char = FactoryBot.create(:verified_registration, user: user)

        post request_api_v1_certificates_path,
             params: { certificate_type: "character_identification", subject_id: verified_char.character.lodestone_id,
                       csr_pem: csr_pem },
             headers: headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to include("No active CA certificate for certificate type")
      end
    end
  end

  describe "POST /api/v1/certificates/:id/revoke" do
    context "with proper scopes" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:revoke certificate:all user character:all") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "revokes user certificate" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers

        expect(response).to have_http_status(:no_content)
        expect(cert.reload.revoked?).to be true
      end

      it "revokes character certificate" do
        verified_char = FactoryBot.create(:verified_registration, user: user)
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)

        post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers

        expect(response).to have_http_status(:no_content)
        expect(cert.reload.revoked?).to be true
      end

      it "revokes certificate from another application" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: other_oauth_client.application)

        post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers

        expect(response).to have_http_status(:no_content)
        expect(cert.reload.revoked?).to be true
      end

      it "returns 400 when reason is missing" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        post revoke_api_v1_certificate_path(cert), headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 400 for invalid revocation reason" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        post revoke_api_v1_certificate_path(cert), params: { reason: "ca_compromise" }, headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 404 for other user's certificate" do
        other_user = FactoryBot.create(:user)
        cert = FactoryBot.create(:pki_issued_certificate, subject: other_user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        without_detailed_exceptions do
          post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 without user scope" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)
        token_without_user = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:revoke certificate:all")

        without_detailed_exceptions do
          post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" },
               headers: { "Authorization" => "Bearer #{token_without_user.token}" }
        end

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 without character scope" do
        verified_char = FactoryBot.create(:verified_registration, user: user)
        cert = FactoryBot.create(:pki_issued_certificate, :for_character_registration, subject: verified_char,
                                 certificate_authority: @ca, requesting_application: oauth_client.application)
        token_without_char = OAuth::AccessToken.create(application: oauth_client, resource_owner: user,
                                                       scopes: "certificate:revoke certificate:all")

        without_detailed_exceptions do
          post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" },
               headers: { "Authorization" => "Bearer #{token_without_char.token}" }
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    context "without certificate:all scope" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:revoke user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "blocks revocation of certificates from other applications" do
        cert = FactoryBot.create(:pki_issued_certificate, subject: user, certificate_authority: @ca,
                                 requesting_application: other_oauth_client.application)

        without_detailed_exceptions do
          post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers
        end

        expect(response).to have_http_status(:not_found)
      end
    end

    context "for entitlement-gated revocation" do
      let(:token) { OAuth::AccessToken.create(application: oauth_client, resource_owner: user, scopes: "certificate:revoke certificate:all user") }
      let(:headers) { { "Authorization" => "Bearer #{token.token}" } }

      it "returns 403 when revoking code_signing certificate without entitlement" do
        cert = FactoryBot.create(:pki_issued_certificate, :code_signing, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        without_detailed_exceptions do
          post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers
        end

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to include("not authorized to revoke")
      end

      it "allows revoking code_signing certificate with entitlement" do
        oauth_client.application.update!(entitlements: ["code_signing_certificates"])
        cert = FactoryBot.create(:pki_issued_certificate, :code_signing, subject: user, certificate_authority: @ca,
                                 requesting_application: oauth_client.application)

        post revoke_api_v1_certificate_path(cert), params: { reason: "superseded" }, headers: headers

        expect(response).to have_http_status(:no_content)
        expect(cert.reload.revoked?).to be true
      end
    end
  end
end
