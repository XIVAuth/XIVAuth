class ClientApp < ActiveRecord::Migration[8.0]
  def up
    create_table :client_applications, id: :uuid do |t|
      t.string :name, null: false
      t.references :owner, type: :uuid, polymorphic: true, null: true, index: true

      t.boolean :private, null: false, default: false
      t.datetime :verified_at, null: true

      t.timestamps
    end

    create_table :client_application_oauth_clients, id: :uuid do |t|
      t.belongs_to :application, type: :uuid, null: false, index: true, foreign_key: { to_table: :client_applications }

      t.string :name, null: false
      t.boolean :enabled, null: false, default: true

      t.string :client_id, null: false, index: { unique: true }
      t.string :client_secret, null: true

      t.string :grant_flows, array: true, default: []
      t.string :redirect_uris, array: true, default: []
      t.string :scopes # doorkeeper *really* doesnt like arrays here

      t.boolean :confidential, null: false, default: true

      t.timestamps
      t.datetime :expires_at, null: true
    end

    create_table :client_application_profiles, id: :uuid do |t|
      t.belongs_to :application, type: :uuid, null: false, index: true, foreign_key: { to_table: :client_applications }

      t.string :icon_url, null: true

      # extra attributes
      t.string :homepage_url, null: true
      t.string :privacy_policy_url, null: true
      t.string :terms_of_service_url, null: true
    end

    # Disable the foreign key constraints on legacy tables
    remove_foreign_key :oauth_access_grants, :oauth_client_applications
    remove_foreign_key :oauth_access_tokens, :oauth_client_applications
    remove_foreign_key :oauth_device_grants, :oauth_client_applications

    perform_data_migration!

    add_foreign_key :oauth_access_grants, :client_application_oauth_clients, column: :application_id
    add_foreign_key :oauth_access_tokens, :client_application_oauth_clients, column: :application_id
    add_foreign_key :oauth_device_grants, :client_application_oauth_clients, column: :application_id
  end

  def down
    remove_foreign_key :oauth_access_grants, :client_application_oauth_clients
    remove_foreign_key :oauth_access_tokens, :client_application_oauth_clients
    remove_foreign_key :oauth_device_grants, :client_application_oauth_clients

    reverse_data_migration!

    add_foreign_key :oauth_access_grants, :oauth_client_applications, column: :application_id
    add_foreign_key :oauth_access_tokens, :oauth_client_applications, column: :application_id
    add_foreign_key :oauth_device_grants, :oauth_client_applications, column: :application_id

    drop_table :client_application_profiles
    drop_table :client_application_oauth_clients
    drop_table :client_applications
  end

  def perform_data_migration!
    OAuth::ClientApplication.all.each do |legacy_app|
      app = ClientApplication.create!(
        id: legacy_app.id,
        name: legacy_app.name,
        owner_id: legacy_app.owner_id,
        owner_type: legacy_app.owner_type,
        created_at: legacy_app.created_at,
        updated_at: legacy_app.updated_at
      )

      oauth_client = ClientApplication::OAuthClient.create!(
        application: app,
        name: "#{legacy_app.name} Legacy Token",
        client_id: legacy_app.uid,
        client_secret: legacy_app.secret,
        scopes: legacy_app.scopes.to_s,
        redirect_uris: legacy_app.redirect_uri.split("\n"),
        confidential: legacy_app.confidential,
        created_at: legacy_app.created_at,
        updated_at: legacy_app.updated_at
      )

      OAuth::AccessGrant.where(application_id: legacy_app.id).update_all(application_id: oauth_client.id)
      OAuth::AccessToken.where(application_id: legacy_app.id).update_all(application_id: oauth_client.id)
      Doorkeeper::DeviceAuthorizationGrant::DeviceGrant.where(application_id: legacy_app.id).update_all(application_id: oauth_client.id)
    end
  end

  def reverse_data_migration!
    ClientApplication.all.each do |modern_app|
      if OAuth::ClientApplication.find_by(id: modern_app.id).present?
        # Don't re-copy data that already exists.
        next
      end

      oauth_client = modern_app.oauth_clients.first

      attrs = {
        id: modern_app.id,
        name: modern_app.name,
        owner_id: modern_app.owner_id,
        owner_type: modern_app.owner_type,
        redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
        scopes: "user",
        created_at: modern_app.created_at,
        updated_at: modern_app.updated_at
      }

      if oauth_client.present?
        attrs.merge!(
          {
            uid: oauth_client.client_id,
            secret: oauth_client.client_secret,
            scopes: oauth_client.scopes.to_s,
            redirect_uri: oauth_client.redirect_uris.join("\n"),
            confidential: oauth_client.confidential
          }
        )
      end

      legacy_app = OAuth::ClientApplication.create!(attrs)

      next unless oauth_client.present?

      OAuth::AccessGrant.where(application_id: oauth_client.id).update_all(application_id: legacy_app.id)
      OAuth::AccessToken.where(application_id: oauth_client.id).update_all(application_id: legacy_app.id)

      Doorkeeper::DeviceAuthorizationGrant::DeviceGrant.where(application_id: oauth_client.id)
                                                       .update_all(application_id: legacy_app.id)
    end
  end
end
