class SharedPrimaryKeysForProfiles < ActiveRecord::Migration[8.1]
  def up
    # user_profiles: make user_id the primary key
    execute "ALTER TABLE user_profiles DROP CONSTRAINT user_profiles_pkey"
    execute "ALTER TABLE user_profiles DROP COLUMN id"
    execute "ALTER TABLE user_profiles ADD PRIMARY KEY (user_id)"
    remove_index :user_profiles, :user_id  # covered by PK index

    # client_application_profiles: make application_id the primary key
    execute "ALTER TABLE client_application_profiles DROP CONSTRAINT client_application_profiles_pkey"
    execute "ALTER TABLE client_application_profiles DROP COLUMN id"
    execute "ALTER TABLE client_application_profiles ADD PRIMARY KEY (application_id)"
    remove_index :client_application_profiles, :application_id  # covered by PK index

    # team_profiles: make team_id the primary key
    execute "ALTER TABLE team_profiles DROP CONSTRAINT team_profiles_pkey"
    execute "ALTER TABLE team_profiles DROP COLUMN id"
    execute "ALTER TABLE team_profiles ADD PRIMARY KEY (team_id)"
    remove_index :team_profiles, :team_id  # covered by PK index
  end

  def down
    # user_profiles
    execute "ALTER TABLE user_profiles DROP CONSTRAINT user_profiles_pkey"
    add_column :user_profiles, :id, :uuid, default: -> { "uuidv7()" }, null: false
    execute "ALTER TABLE user_profiles ADD PRIMARY KEY (id)"
    add_index :user_profiles, :user_id, unique: true

    # client_application_profiles
    execute "ALTER TABLE client_application_profiles DROP CONSTRAINT client_application_profiles_pkey"
    add_column :client_application_profiles, :id, :uuid, default: -> { "uuidv7()" }, null: false
    execute "ALTER TABLE client_application_profiles ADD PRIMARY KEY (id)"
    add_index :client_application_profiles, :application_id

    # team_profiles
    execute "ALTER TABLE team_profiles DROP CONSTRAINT team_profiles_pkey"
    add_column :team_profiles, :id, :uuid, default: -> { "uuidv7()" }, null: false
    execute "ALTER TABLE team_profiles ADD PRIMARY KEY (id)"
    add_index :team_profiles, :team_id
  end
end
