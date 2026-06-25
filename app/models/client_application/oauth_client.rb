class ClientApplication::OAuthClient < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::Application
  include OAuth::ScopesAsArray

  self.table_name = "client_application_oauth_clients" # HACK: Doorkeeper wants to override this.

  belongs_to :application, class_name: "ClientApplication", touch: true

  alias_attribute :uid, :client_id
  alias_attribute :secret, :client_secret

  validate :validate_internal_scopes, if: :scopes_changed?
  validate :validate_redirect_uris_individually

  def redirect_uri
    self.redirect_uris.join("\n")
  end

  def redirect_uri=(val)
    val = val.split("\n") if val.is_a?(String)
    self.redirect_uris = val
  end

  def active?
    self.enabled && !self.expired?
  end

  def expired?
    self.expires_at.present? && self.expires_at < Time.current
  end

  def needs_secret?
    (self.confidential? && (self.grant_flows&.include?("authorization_code") || self.grant_flows&.empty?)) ||
      self.grant_flows&.include?("client_credentials")
  end

  def validate_redirect_uris_individually
    proxy_class = Struct.new(:redirect_uri) { include ActiveModel::Model }
    validator = Doorkeeper::RedirectUriValidator.new(attributes: [:redirect_uri])

    redirect_uris.each_with_index do |uri, index|
      next if uri.blank?

      proxy = proxy_class.new(redirect_uri: uri)
      validator.validate_each(proxy, :redirect_uri, uri)
      proxy.errors.each { |e| errors.add(:redirect_uris, e.type, **e.options.merge(index:)) }
    end
  end

  def validate_internal_scopes
    return if application.entitlement_granted?(:internal)

    self.scopes.select { |s| s.starts_with? "internal" }.each do |scope|
      errors.add(:scopes, :internal_scope, message: "cannot include internal scope: #{scope}")
    end
  end
end
