class ClientApplication::Profile < ApplicationRecord
  belongs_to :application, class_name: "ClientApplication", touch: true

  validates :homepage_url, :privacy_policy_url, :terms_of_service_url, format: {
    with: URI::DEFAULT_PARSER.make_regexp(["https"]),
    message: "must be a valid HTTPS URL"
  }, allow_blank: true
end
