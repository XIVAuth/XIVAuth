class Users::Webauthn::AuthenticateService
  include SemanticLogger::Loggable

  # Initialize a new instance of the webauthn sign-in validation service.
  # @param user [User] The XIVAuth user to authenticate
  # @param device_response [string] The response from the client/webauthn device to validate.
  # @param challenge The challenge from the session to validate against.
  def initialize(user, device_response, challenge)
    @user = user
    @device_response = device_response
    @challenge = challenge
  end

  def execute(discoverable: false, **verification_arguments)
    device_response = JSON.parse(@device_response)
    response_credential = WebAuthn::Credential.from_get(device_response)
    stored_credential = @user.webauthn_credentials.find_by!(external_id: response_credential.id)

    verification_arguments[:user_verification] ||= true if discoverable

    logger.info("Verifying webauthn challenge for user #{@user.id}", response: device_response,
credential: response_credential.id)
    response_credential.verify(@challenge,
                               public_key: stored_credential.public_key,
                               sign_count: stored_credential.sign_count,
                               **verification_arguments)

    stored_credential.update!(sign_count: response_credential.sign_count, last_used_at: Time.current)

    # update passkeys that weren't properly marked as discoverable but were presented accordingly.
    # this is the case for Apple, possibly other keys.
    return unless discoverable && !stored_credential.resident_key

    stored_credential.update!(resident_key: true)
  end

  # Build a new Webauthn challenge for the specified user.
  # @param user [User] The user.
  # @return Returns nil or a WebAuthn::Credential.
  def self.build_challenge_for_user(user)
    return nil if user.webauthn_credentials.blank?

    allowed_credentials = user.webauthn_credentials.map do |cred|
      { type: "public-key", id: cred.external_id, transports: cred.transports }.compact
    end

    WebAuthn::Credential.options_for_get(
      allow_credentials: allowed_credentials,
      user_verification: "discouraged" # acceptable as this is MFA.
    )
  end

  def self.build_discoverable_challenge
    WebAuthn::Credential.options_for_get(
      allow: [],
      user_verification: "required" # necessary to enforce some degree of MFA.
    )
  end
end
