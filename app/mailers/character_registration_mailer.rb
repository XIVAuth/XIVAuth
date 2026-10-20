class CharacterRegistrationMailer < ApplicationMailer
  # @param registration [CharacterRegistration] The character registration that was *invalidated*.
  def character_verified_elsewhere
    @registration = params[:registration]
    @user = @registration.user
    @character = @registration.character

    mail to: @user.email,
         subject: "Security Alert: Your character #{@character.name} was verified by another account",
         template_path: "character_registrations/mailers",
         template_name: "character_clobbered"
  end
end
