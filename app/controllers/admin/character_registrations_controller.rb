class Admin::CharacterRegistrationsController < Admin::AdminController
  before_action :set_context, only: %i[destroy verify unverify]

  def verify
    if @registration.verified?
      respond_to do |format|
        format.html do
          flash[:error] = "Character was already verified."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { render json: { error: "Character already verified." }, status: :unprocessable_content }
      end

      return
    end

    if params[:force]
      @registration.verify!(:administrative, clobber: params[:clobber] == true)

      respond_to do |format|
        format.html do
          flash[:notice] = "Character was successfully force verified."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { head :no_content }
      end

      return
    end

    job = FFXIV::VerifyCharacterRegistrationJob.perform_later @registration
    if job
      respond_to do |format|
        format.json { render status: :created, json: { job_id: job.id } }
        format.html do
          flash[:notice] = "Registration enqueued with Job ID #{job.id}"
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
      end
    else
      respond_to do |format|
        format.json { head :unprocessable_content }
        format.html do
          flash[:error] = "Failed to enqueue verification job?!"
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
      end
    end
  end

  def unverify
    unless @registration.verified?
      respond_to do |format|
        format.html do
          flash[:error] = "Character was already unverified."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { render json: { error: "Character not verified." }, status: :unprocessable_content }
      end

      return
    end

    @registration.unverify

    if @registration.save
      respond_to do |format|
        format.html do
          flash[:alert] = "Character was successfully unverified."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Character could not be unverified."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { head :unprocessable_content }
      end
    end
  end

  def destroy
    if @registration.destroy
      respond_to do |format|
        format.html do
          flash[:alert] = "Character registration successfully deleted."
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Character registration could not be deleted??"
          redirect_back fallback_location: admin_character_path(@registration.character.lodestone_id)
        end
        format.json { head :unprocessable_content }
      end
    end
  end

  def set_context
    @registration = CharacterRegistration.find(params[:id])

    @character = @registration.character
    @user = @registration.user
  end
end
