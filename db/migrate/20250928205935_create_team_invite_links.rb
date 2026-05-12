class CreateTeamInviteLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :team_invite_links, id: :uuid do |t|
      t.references :team, type: :uuid, index: true, foreign_key: { to_table: :teams, on_delete: :cascade }

      t.string :invite_key, null: false, index: { unique: true }

      t.enum :target_role, enum_type: :team_member_roles, null: false, default: "member"

      t.boolean :enabled, null: false, default: true

      t.integer :usage_count, null: false, default: 0, scale: 0
      t.integer :usage_limit, null: true, scale: 0

      t.timestamps
      t.datetime :expires_at, null: true
    end

    remove_column :teams, :invite_secret, :string
  end
end
