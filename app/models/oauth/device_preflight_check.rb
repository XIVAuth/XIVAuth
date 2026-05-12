class OAuth::DevicePreflightCheck
  include ActiveModel::API

  attr_accessor :device_grant, :user
  private :device_grant=
  private :user=

  validates :device_grant, presence: true

  validates_with OAuth::CharacterOwnershipValidator, target_field: :user
  validates_with OAuth::ScopeCompatibilityValidator, target_field: :oauth_client

  def initialize(device_grant, user, attributes = { })
    self.device_grant = device_grant
    self.user = user
    super(attributes)
  end

  delegate :scopes, to: :device_grant

  def oauth_client
    device_grant.application
  end

  def client_application
    oauth_client.application
  end
end
