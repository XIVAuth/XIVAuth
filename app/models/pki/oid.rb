# frozen_string_literal: true

module PKI::OID
  ROOT_OID = "1.3.6.1.4.1.65394.10"

  CUSTOM_FIELDS_ARC = "#{ROOT_OID}.2"
  GLOBAL_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.1"
  CHARACTER_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.2"
  USER_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.3"

  EKU_ARC = "#{ROOT_OID}.3"
  EKU_CharacterIdentification = "#{EKU_ARC}.1"
  EKU_UserIdentification = "#{EKU_ARC}.2"
end