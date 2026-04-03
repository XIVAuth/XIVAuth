class PKI::IssuancePolicy::UserIdentificationPolicy < PKI::IssuancePolicy::Base
  register_certificate_type "user_identification"

  def self.allowed_subject_types = [User]

  def common_name     = "[XIVAuth] #{subject.display_name}"

  def validity_period = 1.year

  def subject_alt_names = %W[
    urn:xivauth:user:#{subject.id}
  ]

  # User certs are pure authentication tokens - digitalSignature only,
  # no key transport or agreement.
  def key_usage = %w[digitalSignature]

  def extended_key_usage = [ PKI::OID::EKU_UserIdentification ]
end
