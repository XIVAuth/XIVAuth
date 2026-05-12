class AddPreferencesField < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :preferences, :jsonb,
               default: { }
    add_index :user_profiles, :preferences, using: :gin
  end
end
