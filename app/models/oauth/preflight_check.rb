class OAuth::PreflightCheck
  include ActiveModel::API

  attr_accessor :pre_authorization
  private :pre_authorization=

  validates :pre_authorization, presence: true

  validates_with OAuth::CharacterOwnershipValidator, target_field: :user
  validates_with OAuth::ScopeCompatibilityValidator, target_field: :oauth_client

  def initialize(pre_authorization, attributes = { })
    self.pre_authorization = pre_authorization
    super(attributes)
  end

  delegate :scopes, to: :pre_authorization

  # helpers
  def user
    pre_authorization.resource_owner
  end

  def oauth_client
    pre_authorization.client.application
  end

  def client_application
    oauth_client.application
  end
end
