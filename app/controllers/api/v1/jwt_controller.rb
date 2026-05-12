class Api::V1::JwtController < Api::V1::ApiController
  skip_before_action :doorkeeper_authorize!, only: %i[jwks]

  def dummy_jwt
    expiry_time = (request.query_parameters[:ttl] || 300).to_i

    # Build JWT using JwtWrapper
    jwt_wrapper = AttestationJwt.new(
      algorithm: params[:algorithm].presence,
      issuer: "#{ENV.fetch('APP_URL', 'https://xivauth.net')}/sandbox",
      claim_type: "xivauth.dummy"
    )

    jwt_wrapper.body["data"] = "dummy jwt for testing"
    jwt_wrapper.body["nonce"] = params[:nonce] if params[:nonce].present?

    # Set expiration if TTL is specified
    if expiry_time.zero?
      jwt_wrapper.expires_at = nil
    else
      jwt_wrapper.expires_in = expiry_time.seconds
    end

    # Set issued_at unless ignore_iat is specified
    jwt_wrapper.issued_at = Time.current if request.query_parameters[:ignore_iat].blank?

    raise ActiveRecord::RecordNotFound if jwt_wrapper.signing_key.blank?

    # Validate and render
    unless jwt_wrapper.valid?
      render json: { errors: jwt_wrapper.errors.full_messages }, status: :unprocessable_content
      return
    end

    token = jwt_wrapper.token

    render json: { token: token }
  end

  def verify
    token = extract_token
    if token.blank?
      render json: { status: "error", error: "No token provided" }, status: :unprocessable_content
      return
    end

    # Parse the encoded token
    encoded_token = JWT::EncodedToken.new(token)

    # Extract kid from header
    kid = encoded_token.header["kid"]
    if kid.blank?
      render json: { status: "error", error: "No kid specified - cannot verify" }, status: :unprocessable_content
      return
    end

    # Look up signing key
    signing_key = JwtSigningKey.find_by(name: kid)
    if signing_key.blank?
      render json: { status: "error", error: "Signing key '#{kid}' not found" }, status: :unprocessable_content
      return
    end

    # Verify signature and standard claims using JWT.decode
    verification_options = {
      verify_iat: params[:ignore_iat].blank?,
      verify_nbf: params[:ignore_nbf].blank?,
      verify_iss: params[:ignore_iss].blank?,
      iss: ENV.fetch("APP_URL", "https://xivauth.net")
    }

    verified_jwt = JWT.decode(
      token,
      signing_key.jwk.verify_key,
      true,
      algorithms: signing_key.supported_algorithms,
      **verification_options
    )

    payload = verified_jwt[0]
    header_data = verified_jwt[1]

    # Manual audience check
    if payload["aud"].present? && params[:ignore_aud].blank?
      issuer_id = doorkeeper_token&.application&.application_id || "_anonymous"
      expected_aud = "#{ENV.fetch('APP_URL', 'https://xivauth.net')}/applications/#{issuer_id}"

      raise JWT::InvalidAudError, "Audience does not match this app's ID" unless payload["aud"] == expected_aud
    end

    # Manual OBO/azp authorization check
    if payload["azp"].present?
      azp_id = payload["azp"].split("/").last
      unless doorkeeper_token.application.application.obo_authorizations.exists?(azp_id)
        raise JWT::InvalidAudError, "Authorized party is not permitted to request a token for this audience"
      end
    end

    render json: { status: "valid", jwt_head: header_data, jwt_body: payload }
  rescue JWT::ExpiredSignature => e
    render status: :unprocessable_content, json: {
      status: "expired",
      error: e.message,
      jwt_head: safe_header(token),
      jwt_body: safe_payload(token)
    }
  rescue JWT::InvalidAudError => e
    render status: :unprocessable_content, json: {
      status: "invalid_client",
      error: e.message,
      jwt_head: safe_header(token),
      jwt_body: safe_payload(token)
    }
  rescue JWT::VerificationError, JWT::DecodeError, JWT::InvalidPayload => e
    render status: :unprocessable_content, json: {
      status: "invalid",
      error: e.message,
      jwt_head: safe_header(token),
      jwt_body: safe_payload(token)
    }
  end

  def jwks
    render json: JwtSigningKey.jwks.export
  end

  private def extract_token
    return params[:token] if params[:token].present?
    return params[:_json] if params[:_json].present? && params.expect(:_json).is_a?(String)

    raw = request.raw_post.to_s.strip
    return if raw.blank?

    # Strip wrapping quotes if present
    raw = raw[1..-2] if raw.start_with?("\"") && raw.end_with?("\"")

    raw.presence
  end

  private def safe_header(token_string)
    JWT.decode(token_string, nil, false)[1]
  rescue StandardError
    nil
  end

  private def safe_payload(token_string)
    JWT.decode(token_string, nil, false)[0]
  rescue StandardError
    nil
  end
end
