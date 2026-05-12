module PKI::OID
  # rubocop:disable Naming/ConstantName
  ROOT_OID = "1.3.6.1.4.1.65394.10".freeze

  CUSTOM_FIELDS_ARC = "#{ROOT_OID}.2".freeze
  GLOBAL_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.1".freeze
  CHARACTER_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.2".freeze
  USER_FIELDS_ARC = "#{CUSTOM_FIELDS_ARC}.3".freeze

  EKU_ARC = "#{ROOT_OID}.3".freeze
  EKU_CharacterIdentification = "#{EKU_ARC}.1".freeze
  EKU_UserIdentification = "#{EKU_ARC}.2".freeze

  EXTENSION_ARC = "#{ROOT_OID}.4".freeze
  EXT_GLOBAL_ARC = "#{EXTENSION_ARC}.1".freeze
  EXT_RequestingApplicationID = "#{EXT_GLOBAL_ARC}.1".freeze
  # rubocop:enable Naming/ConstantName
end
