# Authentication context to use for ACR/AMR resolution.
class Users::AuthnContext
  SESSION_KEY = "authn_context".freeze

  # Maps Users::MFAVerifier results to AMR values.
  MFA_AMR = { totp: "otp", webauthn: "hwk" }.freeze

  def initialize(session)
    @session = session
  end

  # Starts a new context at login, replacing any previous one.
  # @param amr [Array<String>] The methods used to log in.
  # @param mfa [Boolean] Whether the login included an MFA proof.
  def record_login!(amr, mfa: false)
    now = Time.current.to_i
    amr = amr.compact
    amr |= ["mfa"] if mfa

    @session[SESSION_KEY] = { "auth_time" => now, "amr" => amr, "mfa_time" => (now if mfa) }.compact
  end

  # Records an MFA proof made after login.
  # @param method [Symbol] The Users::MFAVerifier result (`:totp`, `:webauthn`), or `:bypass` in development.
  def record_step_up!(method)
    @session[SESSION_KEY] = data.merge(
      "amr" => (amr | [MFA_AMR[method], "mfa"].compact),
      "mfa_time" => Time.current.to_i
    )
  end

  # @param within [ActiveSupport::Duration, Integer] How recent the MFA proof must be. If zero, always require fresh
  # auth.
  def mfa_fresh?(within:)
    return false if within.to_i <= 0 || mfa_time.nil?

    mfa_time > within.ago
  end

  def amr
    data["amr"] || []
  end

  def auth_time
    data["auth_time"] && Time.zone.at(data["auth_time"])
  end

  def mfa_time
    data["mfa_time"] && Time.zone.at(data["mfa_time"])
  end

  private def data
    @session[SESSION_KEY] || { }
  end
end
