class CharacterRegistrationMailerPreview < ActionMailer::Preview
  def character_verified_elsewhere
    user = User.new(email: "preview@example.com", profile: User::Profile.new(display_name: "Preview User"))
    character = FFXIV::Character.new(lodestone_id: 1, name: "Preview Character", home_world: "Gilgamesh", data_center: "Aether")
    registration = CharacterRegistration.new(user: user, character: character)

    CharacterRegistrationMailer.with(registration: registration).character_verified_elsewhere
  end
end
