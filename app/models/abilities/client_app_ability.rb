class Abilities::ClientAppAbility
  include CanCan::Ability

  def initialize(application)
    # NOTE: Application ability to see any given certificate is checked in the controller.

    # Open to all apps — no entitlement required
    can %i[issue revoke], PKI::IssuancePolicy::UserIdentificationPolicy
    can %i[issue revoke], PKI::IssuancePolicy::CharacterIdentificationPolicy

    # Restricted — requires explicit entitlement grant
    return unless application&.entitlement_granted?("code_signing_certificates")

    can %i[issue revoke], PKI::IssuancePolicy::CodeSigningPolicy
  end
end
