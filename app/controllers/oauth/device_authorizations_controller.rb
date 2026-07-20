require "utilities/crockford"

class OAuth::DeviceAuthorizationsController < Doorkeeper::DeviceAuthorizationGrant::DeviceAuthorizationsController
  include OAuth::BuildsPermissiblePolicies

  def index
    # User code is present, shunt over and try to authorize.
    if user_code.present?
      normalized = Crockford.normalize(user_code, split: 4)
      if device_grant.present? && !device_grant.expired?
        new
        return
      elsif device_grant.present? && device_grant.expired?
        device_grant.user_code = normalized
        device_grant.errors.add(:user_code, :expired, message: "has expired.")
      elsif device_grant.nil?
        @device_grant = device_grant_model.new(user_code: normalized)
        @device_grant.errors.add(:user_code, :invalid, message: "was not found.")
      end
    else
      @device_grant = device_grant_model.new
    end

    respond_to do |format|
      format.html
      format.json { head :no_content }
    end
  end

  def new
    device_grant.validate
    @preflight = ::OAuth::DevicePreflightCheck.new(device_grant, current_resource_owner)

    unless @preflight.valid?
      render_preflight_error
      return
    end

    render "oauth/device_authorizations/new", locals: { model: device_grant }
  end

  def authorize
    # Ew.
    if params["disposition"] == "find"
      redirect_to oauth_device_authorizations_index_path(user_code: user_code)
      return
    end

    (destroy and return) if params["disposition"] == "deny"

    if device_grant.nil?
      authorization_error_response(:invalid_user_code)
      return
    end

    if device_grant.expired?
      authorization_error_response(:expired_user_code)
      return
    end

    if device_grant.respond_to?(:permissible_policy)
      policy = build_permissible_policy
      if policy.rules.present?
        policy.save!

        device_grant.permissible_policy = policy
      end
    end

    device_grant.user_code = nil
    device_grant.resource_owner = current_resource_owner

    device_grant.save!

    respond_to do |format|
      format.html do
        redirect_to oauth_device_authorizations_complete_path, flash: { device_authorization_id: device_grant.id }
      end
      format.json { head :no_content }
    end
  end

  def destroy
    if device_grant.nil?
      authorization_error_response(:invalid_user_code)
      return
    end

    device_grant.expires_in = 0

    if device_grant.save
      redirect_to oauth_device_authorizations_index_path, notice: "Device authorization revoked."
    else
      redirect_to oauth_device_authorizations_index_path, alert: "Device authorization could not be revoked."
    end
  end

  def complete
    model_id = flash[:device_authorization_id]
    @device_grant = device_grant_model.find_by(id: model_id)

    if @device_grant.blank?
      redirect_to oauth_device_authorizations_index_path
      return
    end

    render :complete, locals: { model: @device_grant }
  end

  private def device_grant
    return @device_grant if defined?(@device_grant)

    normalized = Crockford.normalize(user_code)
    @device_grant = device_grant_model.find_by(user_code: normalized)
  end

  private def render_preflight_error
    render "oauth/authorizations/preflight_error", status: :bad_request
  end
end
