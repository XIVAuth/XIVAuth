class OAuth::AuthorizationsController < Doorkeeper::AuthorizationsController
  include OAuth::BuildsPermissiblePolicies
  include OAuth::RecordsAuthorizeMetrics

  before_action :set_client_application

  def new
    pre_auth.validate # need to validate first to populate info for preflight

    # Preflight checks
    @preflight = ::OAuth::PreflightCheck.new(pre_auth)

    unless @preflight.valid?
      render_preflight_error
      return
    end

    super
  end

  def create
    # Cheat to get around needing client-side JavaScript to submit a DELETE.
    # The actual DELETE method still works, so this is in addition to compliance, at least.
    (destroy and return) if params["disposition"] == "deny"

    super

    token = @authorize_response.auth.token
    if token.respond_to? :permissible_policy
      policy = build_permissible_policy
      if policy.rules.present?
        policy.save!

        token.permissible_policy = policy
        token.save!
      end
    end

    # log the successful auth to sentry.
    record_authorize_metric(
      oauth_client: @authorize_response.pre_auth.client.application,
      response_type: @authorize_response.pre_auth.response_type,

      # FIXME(DEPS): https://github.com/getsentry/sentry-ruby/issues/2842
      resource_owner_id: @authorize_response.issued_token.resource_owner_id
    )
  end

  private def set_client_application
    return unless params[:client_id].present?

    oauth_client = ClientApplication::OAuthClient.find_by(uid: params[:client_id])
    @client_application = oauth_client&.application
  end

  private def render_preflight_error
    render :preflight_error, status: :bad_request
  end
end
