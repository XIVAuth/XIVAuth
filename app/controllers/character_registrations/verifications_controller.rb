class CharacterRegistrations::VerificationsController < ApplicationController
  before_action :set_character_registration

  def show
    respond_to do |format|
      if @character_registration.verified?
        format.html { redirect_to character_registrations_path, error: "This character is already verified!" }
      else
        format.turbo_stream
        format.html
      end
    end
  end

  def create
    authorize! :update, @character_registration

    @job = FFXIV::VerifyCharacterRegistrationJob.perform_later @character_registration

    respond_to do |format|
      if @job
        format.turbo_stream
        format.html { redirect_to character_registrations_path, notice: "Your verification request has been received!" }
      else
        flash[:error] = "Your verification request could not be submitted at this time. Please try again later."
        format.html { redirect_to character_registrations_path }
      end
    end
  end

  def destroy
    authorize! :manage, @character_registration

    @character_registration.unverify

    respond_to do |format|
      if @character_registration.save
        format.html { redirect_to character_registrations_path, notice: "Character was successfully unverified" }
      else
        format.html { redirect_to character_registrations_path, error: "Could not unverify character." }
      end
    end
  end

  private def set_character_registration
    @character_registration = CharacterRegistration.find(params.expect(:character_registration_id))
    raise ActiveRecord::RecordNotFound unless can? :show, @character_registration

    @character = @character_registration.character
  end
end
