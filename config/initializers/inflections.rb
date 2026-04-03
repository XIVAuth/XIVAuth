# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "person", "people"

  inflect.uncountable "legal"

  inflect.acronym "FFXIV"
  inflect.acronym "XIV"
  inflect.acronym "XIVAPI"
  inflect.acronym "OAuth"
  inflect.acronym "MFA"
  inflect.acronym "OTP"
  inflect.acronym "RSA"
  inflect.acronym "HMAC"
  inflect.acronym "ECDSA"
  inflect.acronym "PKI"
  inflect.acronym "OID"
end
