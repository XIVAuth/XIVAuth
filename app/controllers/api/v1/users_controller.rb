class Api::V1::UsersController < Api::V1::ApiController
  before_action -> { doorkeeper_authorize! :user }
  before_action :check_resource_owner_presence

  before_action only: %i[jwt] do
    doorkeeper_authorize! "user:jwt", "user:manage"
  end

  def show
    @user = current_user
    @social_identities = authorized_social_identities if doorkeeper_token.scopes.exists?("user:social")
  end

  def jwt
    @user = current_user

    # Build JWT using JwtWrapper
    jwt_wrapper = AttestationJwt.new(
      claim_type: "xivauth.user_attestation",
      subject: @user.id,
      expires_in: 10.minutes,
      algorithm: params[:algorithm]
    )

    jwt_wrapper.body["verified"] = @user.character_registrations.verified.any?
    jwt_wrapper.body["nonce"] = params[:nonce] if params[:nonce].present?

    if jwt_wrapper.signing_key.blank?
      render json: { error: "Algorithm is not valid, or a key does not exist for it." }, status: :unprocessable_content
      return
    end

    # Set audience and authorized_party if on-behalf-of requested
    this_app = doorkeeper_token.application.application

    if params[:obo_id].present?
      audience_app = ClientApplication.find(params.expect(:obo_id))

      jwt_wrapper.audience = audience_app
      jwt_wrapper.authorized_party = this_app
    else
      # Set audience to requesting app
      jwt_wrapper.audience = this_app
    end

    # Validate and render
    unless jwt_wrapper.valid?
      render json: { errors: jwt_wrapper.errors.full_messages }, status: :unprocessable_content
      return
    end

    jwt_token = jwt_wrapper.token

    render json: { token: jwt_token }
  end

  private def authorized_social_identities
    policy = @doorkeeper_token.permissible_policy
    identities = @user.social_identities

    policy.present? ? policy.filter_accessible(identities) : identities
  end
end
