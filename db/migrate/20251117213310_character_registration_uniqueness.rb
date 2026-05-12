class CharacterRegistrationUniqueness < ActiveRecord::Migration[8.1]
  def change
    add_index :character_registrations, %i[character_id user_id], unique: true
  end
end
