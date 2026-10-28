# Gates controller actions behind a recent MFA proof ("sudo mode").
#
#   requires_sudo only: :destroy, within: 0, and_rerender: :render_destroy_modal, fallback: :confirm_name!
#
# - `within:` how recent the user's last MFA proof must be. `0` means the proof must arrive with this request.
# - `and_rerender:` a method, called as `method(error: nil)`, that renders the UI holding the MFA challenge (the
#   `users/sudo_mode/challenge_fields` partial). It's called with no error when a challenge is needed, and with a
#   message when a proof was rejected. It must render.
# - `fallback:` (optional) a method to run instead when the user has no MFA. It may render/redirect to halt the action.
#
# A proof is accepted from `params[:sudo]`, verified with Users::MFAVerifier, and recorded as the session's latest
# `mfa_time` in Users::AuthnContext (logging in with MFA sets it too). Any later action with a large enough `within:`
# passes without asking again. Failed proofs are rate-limited by Users::StepUpLockout.
#
# There are two ways to lay out the UI:
#
# 1. Challenge inside the action's own modal (removing an authenticator, deleting something). Use `within: 0`.
#    The button that opens the modal sends the action's own request with no proof, which re-renders as the modal. The
#    modal's form embeds `challenge_fields`, so confirming sends the proof along with the action.
#
#      requires_sudo only: :destroy, within: 0, and_rerender: :render_destroy_modal
#
#      private def render_destroy_modal(error: nil)
#        render_sudo_modal(modal_id: "remove_thing_modal", partial: "things/destroy_modal", error: error)
#      end
#
# 2. Challenge first, then show the real form (adding an authenticator). Gate both `new` and `create` with a short
#    window, and add a `POST .../new` route (`as: nil`). The challenge renders `users/sudo_mode/modal_challenge`, which
#    posts the proof back to `new`; `new` then runs normally and its turbo_stream template updates the open modal with
#    the real form (`request.post?` means "came from the challenge"). If the grant runs out before `create`, the
#    same challenge is shown in the open modal and the flow starts over.
#
#      requires_sudo only: %i[new create], within: 5.minutes, and_rerender: :render_sudo_challenge
module Users::RequiresSudo
  extend ActiveSupport::Concern

  included do
    helper_method :sudo_applicable?, :sudo_webauthn_challenge
  end

  class_methods do
    def requires_sudo(within:, and_rerender:, fallback: nil, **filter_options)
      before_action(**filter_options) do
        require_sudo!(within: within, rerender: and_rerender, fallback: fallback)
      end
    end
  end

  # Whether sudo mode applies to the current user. Views use this to choose between the MFA challenge and the action's
  # regular confirmation.
  def sudo_applicable?
    current_user&.mfa_enabled? || false
  end

  # Builds (once per request) a WebAuthn challenge for sudo and stores it for verification.
  def sudo_webauthn_challenge
    return @sudo_webauthn_challenge if defined?(@sudo_webauthn_challenge)

    @sudo_webauthn_challenge = Users::Webauthn::AuthenticateService.build_challenge_for_user(current_user)
    session[:sudo_webauthn_challenge] = @sudo_webauthn_challenge&.challenge
    @sudo_webauthn_challenge
  end

  def authn_context
    @authn_context ||= Users::AuthnContext.new(session)
  end

  private def step_up_lockout
    @step_up_lockout ||= Users::StepUpLockout.new(session)
  end

  private def require_sudo!(within:, rerender:, fallback: nil)
    unless sudo_applicable?
      send(fallback) if fallback
      return
    end

    return if authn_context.mfa_fresh?(within: within)

    error = if sudo_proof_present?
              verify_sudo_proof
            elsif sudo_params[:prompted].present?
              # The challenge form was submitted without a proof.
              "Use a security key or enter a code to continue."
            else
              # First contact: show the challenge.
              send(rerender)
              return
            end

    return if error.nil?

    @sudo_error = error
    send(rerender, error: error)
  end

  # Verifies the submitted proof and records a grant.
  # @return [String, nil] An error message, or nil on success.
  private def verify_sudo_proof
    return "Too many failed attempts. Please wait a few minutes and try again." if step_up_lockout.locked_out?

    if sudo_params[:bypass_mfa].present? && Rails.env.development?
      authn_context.record_step_up!(:bypass)
      return nil
    end

    method = Users::MFAVerifier.new(
      current_user,
      otp_attempt: sudo_params[:otp_attempt],
      webauthn_response: sudo_params[:webauthn_response],
      webauthn_challenge: session.delete(:sudo_webauthn_challenge)
    ).verify!

    authn_context.record_step_up!(method)
    step_up_lockout.reset!
    nil
  rescue Users::MFAVerifier::VerificationError => e
    step_up_lockout.record_failure!
    "Verification via #{e.method} failed: #{e.message}"
  rescue ActiveRecord::RecordNotFound
    step_up_lockout.record_failure!
    "That security key is not registered to your account."
  end

  private def sudo_proof_present?
    sudo_params.slice(:otp_attempt, :webauthn_response, :bypass_mfa).values.any?(&:present?)
  end

  private def sudo_params
    params.permit(sudo: %i[otp_attempt webauthn_response bypass_mfa prompted]).fetch(:sudo, { })
  end

  # Renders `partial` into a remote modal, for use from an `and_rerender:` method. The modal is opened on first contact
  # and its content replaced when re-prompting after an error; pass `update: true` to always replace (e.g. when the
  # modal is already open for another reason).
  private def render_sudo_modal(modal_id:, partial:, locals: { }, error: nil, update: error.present?)
    render "users/sudo_mode/modal",
           locals: { modal_id: modal_id, partial: partial, partial_locals: locals, update: update },
           formats: [:turbo_stream],
           status: error ? :unprocessable_content : :ok
  end
end
