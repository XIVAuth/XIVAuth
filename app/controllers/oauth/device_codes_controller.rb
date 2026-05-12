class OAuth::DeviceCodesController < Doorkeeper::DeviceAuthorizationGrant::DeviceCodesController
  before_action :do_preflight!, only: :create

  def create
    super
  end

  def do_preflight!
    @request = strategy.request

    # Scope validation
    invalid_scopes = OAuth::ScopeCompatibilityValidator.find_incompatible_scopes(@request.scopes)
    return if invalid_scopes.empty?

    rep = invalid_scopes.map { |s| s.join(",") }.join(" | ")
    render status: :unprocessable_content, json: {
      error: "incompatible_scopes",
      error_description: "The following scope combinations are incompatible: #{rep}."
    }
  end
end
