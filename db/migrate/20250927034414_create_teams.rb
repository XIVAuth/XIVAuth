class CreateTeams < ActiveRecord::Migration[8.0]
  def change
    create_enum :team_member_roles, %w[admin developer member invited blocked]

    create_table :teams, id: :uuid do |t|
      t.string :name, null: false

      t.references :parent, type: :uuid, index: true, foreign_key: { to_table: :teams, on_delete: :cascade }
      t.boolean :inherit_parent_memberships, null: false, default: true

      t.string :invite_secret, null: true, index: { unique: true }

      t.timestamps
      t.datetime :verified_at, null: true
    end

    create_table :team_memberships, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.enum :role, enum_type: :team_member_roles, null: false, default: "member"

      t.timestamps
    end

    create_table :team_profiles, id: :uuid do |t|
      t.references :team, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.string :avatar_url, null: true
      t.string :website_url, null: true

      t.timestamps
    end
  end
end
