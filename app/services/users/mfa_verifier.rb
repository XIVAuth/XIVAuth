# Verifies a second-factor proof (TOTP/backup code or WebAuthn assertion) for a user. Shared by login and sudo mode.
class Users::MFAVerifier
  class VerificationError < StandardError
    attr_reader :method

    def initialize(method, message)
      @method = method
      super(message)
    end
  end

  # @param user [User] The user to verify.
  # @param otp_attempt [String, nil] A TOTP or backup code.
  # @param webauthn_response [String, nil] The JSON response from the client's WebAuthn device.
  # @param webauthn_challenge [String, nil] The challenge previously issued for this verification.
  def initialize(user, otp_attempt: nil, webauthn_response: nil, webauthn_challenge: nil)
    @user = user
    @otp_attempt = otp_attempt
    @webauthn_response = webauthn_response
    @webauthn_challenge = webauthn_challenge
  end

  # @return [Symbol] The method used (`:totp` or `:webauthn`).
  # @raise [VerificationError] if no proof was supplied or the proof was invalid.
  def verify!
    if @otp_attempt.present?
      verify_totp!
    elsif @webauthn_response.present?
      verify_webauthn!
    else
      raise VerificationError.new("setup", "invalid context")
    end
  end

  private def verify_totp!
    raise VerificationError.new("TOTP", "TOTP is not configured!") unless @user.totp_credential&.otp_enabled

    unless @user.totp_credential.validate_and_consume_otp_or_backup!(@otp_attempt)
      raise VerificationError.new("TOTP", "TOTP was invalid or could not be verified.")
    end

    :totp
  end

  private def verify_webauthn!
    raise VerificationError.new("WebAuthn", "no challenge was issued") if @webauthn_challenge.blank?

    Users::Webauthn::AuthenticateService.new(@user, @webauthn_response, @webauthn_challenge).execute
    :webauthn
  rescue WebAuthn::Error => e
    raise VerificationError.new("WebAuthn", e.message)
  end
end
