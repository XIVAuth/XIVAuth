class AddTeamMembershipUniqueness < ActiveRecord::Migration[8.1]
  def change
    add_index :team_memberships, %i[team_id user_id], unique: true
  end
end
