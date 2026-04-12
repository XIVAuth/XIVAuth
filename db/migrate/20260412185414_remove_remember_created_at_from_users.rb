class RemoveRememberCreatedAtFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :remember_created_at, :datetime
  end
end
