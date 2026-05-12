class Doorkeeper::GrantDataAttacher
  def self.attach(request, response)
    return unless response.is_a?(Doorkeeper::OAuth::TokenResponse)

    grant_flow = if request.is_a?(Doorkeeper::OAuth::RefreshTokenRequest)
                   Doorkeeper::OAuth::REFRESH_TOKEN
                 elsif request.respond_to?(:grant_type)
                   request.grant_type
                 end

    response.token.source_grant_flow = grant_flow
    response.token.save
  end
end
