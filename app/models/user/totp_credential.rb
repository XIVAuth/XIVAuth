class User::TotpCredential < ApplicationRecord
  BACKUP_CODE_COUNT = 5
  BACKUP_CODE_BYTELEN = 6

  belongs_to :user

  devise :two_factor_authenticatable,
         :two_factor_backupable,
         otp_backup_code_length: BACKUP_CODE_BYTELEN,
         otp_number_of_backup_codes: BACKUP_CODE_COUNT

  def validate_and_consume_otp_or_backup!(code) # rubocop:disable Naming/PredicateMethod
    return true if validate_and_consume_otp!(code)

    if invalidate_otp_backup_code!(code)
      save(validate: false)
      return true
    end

    false
  end

  def otp_provisioning_uri
    issuer = "XIVAuth"
    super("[#{issuer}] #{user.email}", issuer: issuer)
  end
end
