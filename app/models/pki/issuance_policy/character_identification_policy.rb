class PKI::IssuancePolicy::CharacterIdentificationPolicy < PKI::IssuancePolicy::Base
  register_certificate_type "character_identification"

  def self.allowed_subject_types = [CharacterRegistration]

  # CN is a human-friendly snapshot of the character's name and world at issuance time.
  # Consumers MUST use the SAN URI for identity, not the CN - it may become stale on
  # character transfers/renames without invalidating the certificate.
  def common_name     = "[XIVAUTH] #{subject.character.name} @ #{subject.character.home_world}"
  def validity_period = 1.year

  def subject_alt_names = %W[
    urn:xivauth:character:lodestone:#{subject.character.lodestone_id}
    urn:xivauth:character:persistent_key:#{subject.entangled_id}
  ]

  def key_usage
    case public_key
    when OpenSSL::PKey::EC  then %w[digitalSignature keyAgreement]
    when OpenSSL::PKey::RSA then %w[digitalSignature keyEncipherment]
    else %w[digitalSignature]
    end
  end

  def extended_key_usage = [ PKI::OID::EKU_CharacterIdentification ]

  # Snapshot the stable character identity at issuance for audit purposes.
  # Survives CharacterRegistration deletion since the cert record persists.
  def issuance_context
    {
      "persistent_key" => subject.entangled_id,
      "lodestone_id"   => subject.character.lodestone_id.to_s,
      "user_id"        => subject.user_id.to_s
    }
  end

  # CharacterRegistrations must be verified before certs can be issued.
  validate :validate_character_verified

  private def validate_character_verified
    errors.add(:subject, "CharacterRegistration must be verified") unless subject.verified?
  end
end
