class Api::V1::CharactersController < Api::V1::ApiController
  include Api::FiltersAuthorizedCharacters

  before_action { doorkeeper_authorize! "character", "character:all", "character:manage", "character:jwt" }
  before_action(except: %i[index show jwt]) { doorkeeper_authorize! "character:manage" }
  before_action(only: %i[jwt]) { doorkeeper_authorize! "character:jwt", "character:manage" }

  before_action :check_resource_owner_presence
  before_action :load_authorized_characters
  before_action :set_character, except: %i[index create]

  def index
    @registrations = @authorized_registrations.includes(:character)

    sp = search_params
    @registrations = @registrations.joins(:character).where(character: sp.to_hash) if sp.present?
  end

  def show; end

  def create
    request_params = {
      user: current_user,
      lodestone_url: params[:lodestone_id]
    }

    # If name and world are provided, use search path
    if params[:name].present? && params[:world].present?
      request_params = {
        user: current_user,
        search_name: params[:name],
        search_world: params[:world],
        search_exact: params[:exact].to_s == "true"
      }
    end

    registration_request = CharacterRegistrationRequest.new(request_params)

    case registration_request.process!
    when :success
      @registration = registration_request.created_registration
      render :show, status: :created, location: @registration
    when :confirm
      # For API, return candidates for the client to choose from
      render json: {
        status: "search_selection_required",
        message: "Multiple matching characters found. Please specify which character to register.",
        candidates: registration_request.candidates
      }, status: :multiple_choices
    else
      render json: { errors: registration_request.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    authorize! :update, @registration

    @registration.character.update(update_params)

    if @registration.save
      render :show, status: :ok, location: @registration
    else
      render json: { errors: @registration.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    authorize! :destroy, @registration

    @registration.destroy

    head :no_content
  end

  def verify
    authorize! :update, @registration

    if FFXIV::VerifyCharacterRegistrationJob.perform_later @registration
      head status: :created
    else
      head status: :internal_server_error
    end
  end

  def unverify
    authorize! :update, @registration

    @registration.unverify

    if @registration.save
      head status: :no_content
    else
      render json: { errors: @registration.errors.full_messages }, status: :unprocessable_content
    end
  end

  def jwt
    unless @registration.verified?
      render json: { error: "Attestations can only be generated for verified characters." }, status: :forbidden
      return
    end

    # Build JWT using JwtWrapper
    jwt_wrapper = AttestationJwt.new(
      body_attrs: {
        sub: @registration.character.lodestone_id,
        pk: @registration.entangled_id
      },
      claim_type: "xivauth.character_attestation",
      expires_in: 10.minutes,
      algorithm: (params[:algorithm] if params[:algorithm].present?),
      nonce: (params[:nonce] if params[:nonce].present?)
    )

    client_app = doorkeeper_token.application.application

    if params[:obo_id].present?
      audience_app = ClientApplication.find(params[:obo_id])

      jwt_wrapper.audience = audience_app
      jwt_wrapper.authorized_party = client_app
    else
      # Set audience to requesting app
      jwt_wrapper.audience = client_app
    end

    # Validate and render
    unless jwt_wrapper.valid?
      render json: { errors: jwt_wrapper.errors.full_messages }, status: :unprocessable_content
      return
    end

    jwt_token = jwt_wrapper.token

    render json: { token: jwt_token }
  end

  private def load_authorized_characters
    @authorized_registrations = authorized_character_registrations
  end

  private def set_character
    character = @authorized_registrations.filter do |r|
      r.character.lodestone_id == params[:lodestone_id]
    end

    raise ActiveRecord::RecordNotFound if character[0].nil?

    @registration = character[0]
  end

  private def search_params
    allowlist = %i[name home_world data_center]
    allowlist << :content_id if has_character_manage_scope?

    params.permit(allowlist)
  end

  private def update_params
    params.permit(:content_id)
  end

  private def character_manage?
    has_character_manage_scope?
  end
end
