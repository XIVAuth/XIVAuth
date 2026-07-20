module OAuth::RecordsAuthorizeMetrics
  extend ActiveSupport::Concern

  def record_authorize_metric(oauth_client:, response_type:, resource_owner_id:)
    Sentry.metrics.count(
      "xivauth.application.authorize",
      value: 1,
      attributes: {
        "oauth_params.response_type": response_type,

        "application.client_id": oauth_client.id,
        "application.app_id": oauth_client.application.id,
        "application.app_name": oauth_client.application.name,

        "user.id": resource_owner_id
      }
    )
  end
end
