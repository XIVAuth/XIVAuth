class AddPreferencesToUser < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferences, :jsonb, default: {}
  end
end
