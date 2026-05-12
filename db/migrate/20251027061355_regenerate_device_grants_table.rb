class RegenerateDeviceGrantsTable < ActiveRecord::Migration[8.1]
  def change
    drop_table :oauth_device_grants do
    end

    create_table :oauth_device_grants, id: :uuid do |t|
      t.references :application, type: :uuid, null: false, index: true,
foreign_key: { to_table: :client_application_oauth_clients }
      t.references :resource_owner, type: :uuid, index: true, polymorphic: true

      t.string :device_code, null: false, index: { unique: true }
      t.string :user_code, null: true, index: { unique: true }

      t.string :scopes, null: false, default: ""
      t.references :permissible_policy, type: :uuid, null: true, foreign_key: { to_table: :oauth_permissible_policies }

      t.integer :expires_in, null: false

      t.datetime :created_at, null: false
      t.datetime :last_polling_at, null: true
    end
  end
end
