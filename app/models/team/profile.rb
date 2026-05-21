class Team::Profile < ApplicationRecord
  self.primary_key = :team_id

  belongs_to :team, class_name: "Team", inverse_of: :profile
end
