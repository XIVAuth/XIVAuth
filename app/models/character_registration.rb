require "utilities/crockford"

# {CharacterRegistration} represents a mapping between a game character and a claim by any specific user.
# Character registrations are only considered "effective" if they have been verified in some way.
#
# @!attribute source [string] The original source of this character registration, often used if this character
#                             was imported from another site.
# @!attribute verification_type [string] The means by which this specific character was verified. Varies based on
#                                        character type and other factors.
class CharacterRegistration < ApplicationRecord
  VERIFICATION_KEY_PREFIX = "XIVAUTH:".freeze
  VERIFICATION_KEY_LENGTH = 24
  VERIFICATION_KEY_REGEX = /#{VERIFICATION_KEY_PREFIX}[#{Crockford::ENCODER.join('')}]{#{VERIFICATION_KEY_LENGTH}}/i

  belongs_to :user
  belongs_to :character, class_name: "FFXIV::Character"

  validates :character_id, uniqueness: { scope: [:user_id], message: "is already registered to you!" }
  validates :character_id,
            uniqueness: { conditions: -> { where.not(verified_at: nil) },
                          if: -> { !verified_at.nil? },
                          message: "has already been verified." }

  validates :verification_type, presence: true, if: -> { self.verified? }
  validates :verification_type, absence: true, unless: -> { self.verified? }

  attr_accessor :skip_ban_check

  validate :validate_linked_character
  validate :character_not_banned, unless: :skip_ban_check, on: :create
  validate :owner_can_create, on: :create

  has_many :pki_issued_certificates, class_name: "PKI::IssuedCertificate",
           as: :subject

  after_update  :broadcast_card_update
  after_update  :revoke_pki_certificates_if_unverified
  after_destroy :revoke_pki_certificates_on_destroy

  scope :verified, -> { where.not(verified_at: nil) }
  scope :unverified, -> { where(verified_at: nil) }

  def verified?
    verified_at.present?
  end

  # Mark the targeted CharacterRegistration as verified, optionally unverifying any other registrations that may be present.
  # This method will attempt to save all modified CharacterRegistrations.
  # @param clobber [Boolean] When true, unverify the prior CharacterRegistration.
  # @param send_email [Boolean] When true, email the prior owner if their character was clobbered.
  def verify!(verification_type, clobber: false, send_email: false)
    transaction do
      other_registration = CharacterRegistration.verified.find_by(character_id:)

      if other_registration.present? && clobber
        logger.warn("Character verification was clobbered!", old: other_registration, new: self)
        other_registration.unverify
        other_registration.save!

        if send_email
          CharacterRegistrationMailer.with(registration: other_registration).character_verified_elsewhere.deliver_later
        end
      end

      self.verify(verification_type)
      save!
    rescue ActiveRecord::RecordInvalid
      self.unverify
      raise
    end
  end

  def verify(verification_type)
    self.verified_at = DateTime.now
    self.verification_type = verification_type
  end

  def unverify
    self.verified_at = nil
    self.verification_type = nil
  end

  def verification_key
    # TODO: Load secret from environment, don't use lodestone_id as it's not reusable (other models in future)
    secret = Rails.application.key_generator.generate_key("CharacterVerificationSecret")
    hmac = OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, "#{character.lodestone_id}###{user.id}")

    "#{VERIFICATION_KEY_PREFIX}#{Crockford.encode_string(hmac)&.truncate(VERIFICATION_KEY_LENGTH, omission: '')}"
  end

  # Generates a "entangled ID" suitable for unique, consistent, and private identification of a single Character 
  # Registration. This ID should be used for any authentication systems that want to verify based on character ID while
  # ensuring user guarantees.
  def entangled_id(higher_order_id: nil)
    entanglement_key = "#{character.lodestone_id}###{user.id}"
    entanglement_key += "###{higher_order_id}" if higher_order_id.present?

    # TODO: Think of a better strategy for this
    secret = Rails.application.key_generator.generate_key("CharacterEntanglementSecret")
    hmac = OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha1"), secret, entanglement_key)

    Base64.urlsafe_encode64(hmac, padding: false)
  end

  # Create a new (unsaved) CharacterRegistration from a Lodestone ID
  # @param user [User] The user registering the character
  # @param lodestone_id [String, Integer] The Lodestone character ID
  # @param extra_data [Hash] Optional extra data to merge (e.g., { region: "na" })
  # @return [CharacterRegistration] Unsaved registration (call .save to persist)
  def self.build_from_lodestone(user:, lodestone_id:, extra_data: {})
    character = FFXIV::Character.for_lodestone_id(lodestone_id)
    registration = new(character: character, user: user)
    registration.extra_data.merge!(extra_data) if extra_data.present?
    registration
  end

  def lodestone_url(region: nil)
    region ||= self.extra_data.fetch("region", "na")
    self.character.lodestone_url(region)
  end

  def broadcast_card_update
    broadcast_replace_to(
      "UserStream:#{user.id}", :character_registrations,
      target: "character_registration_#{self.id}",
      partial: "character_registrations/character_card"
    )
  end

  private def revoke_pki_certificates_if_unverified
    return unless saved_change_to_verified_at? && verified_at.nil?
    pki_issued_certificates.active.find_each { |c| c.revoke!(reason: "affiliation_changed") }
  end

  private def revoke_pki_certificates_on_destroy
    pki_issued_certificates.active.find_each { |c| c.revoke!(reason: "affiliation_changed") }
  end

  private def owner_can_create
    return unless user.character_registrations.unverified.count >= user.unverified_character_allowance

    errors.add(:base, :too_many_unverified, message: "You have too many unverified characters.")
  end

  private def character_not_banned
    return if character.nil?  # handled elsewhere

    # Character bans exist to prevent users from trying to register certain "VIP" or other high-profile charcters.
    # Rather than waste time and resources on verifying them, we simply wait for admin intervention.
    # The character ban system *may* also be used for fraud and abuse, but that is not its primary purpose.
    return unless character.ban.present? && !skip_ban_check

    errors.add(:base, :banned,
               message: "Character cannot be registered directly. Please contact an XIVAuth developer.")
  end

  private def validate_linked_character
    return if character.nil? # handled elsewhere
    return if character.validate

    base_errors = character.errors.where(:base) || []
    if base_errors.present?
      errors.add(:character, base_errors.first.type, message: base_errors.first.message)
    else
      logger.error("Validation failed for character with Lodestone ID #{character.lodestone_id}.",
                   errors: character.errors)

      errors.add(:character, :process_failed, message: "could not be found or processed.")
    end
  end
end
