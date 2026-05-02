# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_01_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "ffxiv_character_refresh_error", ["UNSPECIFIED", "HIDDEN_CHARACTER", "PROFILE_PRIVATE", "NOT_FOUND", "LODESTONE_MAINTENANCE"]
  create_enum "pki_certificate_type", ["character_identification", "user_identification", "code_signing"]
  create_enum "pki_revocation_reason", ["unspecified", "key_compromise", "ca_compromise", "affiliation_changed", "superseded", "cessation_of_operation", "certificate_hold", "privilege_withdrawn", "aa_compromise"]
  create_enum "team_member_roles", ["admin", "manager", "developer", "member", "invited", "blocked"]
  create_enum "user_roles", ["developer", "admin"]

  create_table "attachments", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "file_data"
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_attachments_on_record_type_and_record_id_and_name"
  end

  create_table "character_bans", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "character_id"
    t.string "character_type"
    t.datetime "created_at", null: false
    t.string "reason"
    t.index ["character_type", "character_id"], name: "index_character_bans_on_character"
  end

  create_table "character_registrations", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "character_id"
    t.datetime "created_at", null: false
    t.jsonb "extra_data", default: {}, null: false
    t.string "source", default: "internal", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.string "verification_type"
    t.datetime "verified_at"
    t.index ["character_id", "user_id"], name: "index_character_registrations_on_character_id_and_user_id", unique: true
    t.index ["character_id"], name: "index_character_registrations_on_character_id"
    t.index ["user_id"], name: "index_character_registrations_on_user_id"
  end

  create_table "client_application_access_control_lists", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.datetime "created_at", null: false
    t.boolean "deny", default: false, null: false
    t.boolean "include_team_descendants", default: false, null: false
    t.uuid "principal_id", null: false
    t.string "principal_type", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id"], name: "idx_on_application_id_352d79df92"
    t.index ["principal_type", "principal_id"], name: "index_client_application_access_control_lists_on_principal"
  end

  create_table "client_application_oauth_clients", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.string "client_id", null: false
    t.string "client_secret"
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "expires_at"
    t.string "grant_flows", default: [], array: true
    t.string "name", null: false
    t.string "redirect_uris", default: [], array: true
    t.string "scopes", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["application_id"], name: "index_client_application_oauth_clients_on_application_id"
    t.index ["client_id"], name: "index_client_application_oauth_clients_on_client_id", unique: true
  end

  create_table "client_application_obo_authorizations", id: false, force: :cascade do |t|
    t.uuid "audience_id", null: false
    t.uuid "authorized_party_id", null: false
    t.index ["audience_id", "authorized_party_id"], name: "idx_on_audience_id_authorized_party_id_eaac01738f", unique: true
    t.index ["audience_id"], name: "index_client_application_obo_authorizations_on_audience_id"
    t.index ["authorized_party_id"], name: "idx_on_authorized_party_id_2afcfbe007"
  end

  create_table "client_application_profiles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.string "homepage_url"
    t.string "icon_url"
    t.string "privacy_policy_url"
    t.string "terms_of_service_url"
    t.index ["application_id"], name: "index_client_application_profiles_on_application_id"
  end

  create_table "client_applications", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entitlements", default: [], null: false, array: true
    t.string "name", null: false
    t.uuid "owner_id"
    t.string "owner_type"
    t.boolean "private", default: false, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["owner_type", "owner_id"], name: "index_client_applications_on_owner"
  end

  create_table "ffxiv_characters", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "avatar_url", null: false
    t.string "content_id"
    t.datetime "created_at", null: false
    t.string "data_center", null: false
    t.string "home_world", null: false
    t.string "lodestone_id", null: false
    t.string "name", null: false
    t.string "portrait_url", null: false
    t.enum "refresh_fail_reason", enum_type: "ffxiv_character_refresh_error"
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_ffxiv_characters_on_content_id", unique: true, where: "((content_id IS NOT NULL) OR ((content_id)::text <> ''::text))"
    t.index ["lodestone_id"], name: "index_ffxiv_characters_on_lodestone_id", unique: true
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "jwt_signing_keys", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "expires_at"
    t.jsonb "key_params", default: {}
    t.string "name"
    t.string "private_key", limit: 65535, null: false
    t.string "public_key", limit: 65535
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_jwt_signing_keys_on_name", unique: true
  end

  create_table "oauth_access_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.uuid "permissible_policy_id"
    t.text "redirect_uri", null: false
    t.uuid "resource_owner_id", null: false
    t.string "resource_owner_type", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: [], null: false, array: true
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["permissible_policy_id"], name: "index_oauth_access_grants_on_permissible_policy_id"
    t.index ["resource_owner_type", "resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.uuid "permissible_policy_id"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.uuid "resource_owner_id"
    t.string "resource_owner_type"
    t.datetime "revoked_at"
    t.string "scopes", default: [], null: false, array: true
    t.string "source_grant_flow"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["permissible_policy_id"], name: "index_oauth_access_tokens_on_permissible_policy_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true, where: "((refresh_token IS NOT NULL) OR ((refresh_token)::text <> ''::text))"
    t.index ["resource_owner_type", "resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_device_grants", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "application_id", null: false
    t.datetime "created_at", null: false
    t.string "device_code", null: false
    t.integer "expires_in", null: false
    t.datetime "last_polling_at"
    t.uuid "permissible_policy_id"
    t.uuid "resource_owner_id"
    t.string "resource_owner_type"
    t.string "scopes", default: [], null: false, array: true
    t.string "user_code"
    t.index ["application_id"], name: "index_oauth_device_grants_on_application_id"
    t.index ["device_code"], name: "index_oauth_device_grants_on_device_code", unique: true
    t.index ["permissible_policy_id"], name: "index_oauth_device_grants_on_permissible_policy_id"
    t.index ["resource_owner_type", "resource_owner_id"], name: "index_oauth_device_grants_on_resource_owner"
    t.index ["user_code"], name: "index_oauth_device_grants_on_user_code", unique: true
  end

  create_table "oauth_permissible_policies", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
  end

  create_table "oauth_permissible_rules", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "deny", default: false
    t.uuid "policy_id"
    t.string "resource_id"
    t.string "resource_type"
    t.index ["policy_id"], name: "index_oauth_permissible_rules_on_policy_id"
    t.index ["resource_type", "resource_id"], name: "index_oauth_permissible_rules_on_resource"
  end

  create_table "pki_certificate_authorities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.enum "allowed_certificate_types", default: ["user_identification", "character_identification"], null: false, array: true, enum_type: "pki_certificate_type"
    t.string "certificate_fingerprint", null: false
    t.text "certificate_pem", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.text "private_key", null: false
    t.string "public_key_fingerprint", null: false
    t.enum "revocation_reason", enum_type: "pki_revocation_reason"
    t.datetime "revoked_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_pki_certificate_authorities_on_active"
    t.index ["certificate_fingerprint"], name: "index_pki_certificate_authorities_on_certificate_fingerprint", unique: true
    t.index ["public_key_fingerprint"], name: "index_pki_certificate_authorities_on_public_key_fingerprint"
    t.index ["slug"], name: "index_pki_certificate_authorities_on_slug", unique: true
  end

  create_table "pki_issued_certificates", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "certificate_authority_id", null: false
    t.string "certificate_fingerprint", null: false
    t.text "certificate_pem", null: false
    t.enum "certificate_type", null: false, enum_type: "pki_certificate_type"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.jsonb "issuance_context", default: {}, null: false
    t.datetime "issued_at", null: false
    t.string "public_key_fingerprint", null: false
    t.jsonb "public_key_info", default: {}, null: false
    t.uuid "requesting_application_id"
    t.enum "revocation_reason", enum_type: "pki_revocation_reason"
    t.datetime "revoked_at"
    t.uuid "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index ["certificate_authority_id"], name: "index_pki_issued_certificates_on_certificate_authority_id"
    t.index ["certificate_fingerprint"], name: "index_pki_issued_certificates_on_certificate_fingerprint", unique: true
    t.index ["public_key_fingerprint"], name: "index_pki_issued_certificates_on_public_key_fingerprint"
    t.index ["requesting_application_id"], name: "index_pki_issued_certificates_on_requesting_application_id"
    t.index ["subject_type", "subject_id"], name: "index_pki_issued_certificates_on_subject"
  end

  create_table "site_announcements", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "end_date"
    t.datetime "start_date"
    t.text "title"
    t.text "type"
    t.datetime "updated_at", null: false
  end

  create_table "team_invite_links", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "expires_at"
    t.string "invite_key", null: false
    t.enum "target_role", default: "member", null: false, enum_type: "team_member_roles"
    t.uuid "team_id"
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.integer "usage_limit"
    t.index ["invite_key"], name: "index_team_invite_links_on_invite_key", unique: true
    t.index ["team_id"], name: "index_team_invite_links_on_team_id"
  end

  create_table "team_memberships", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.enum "role", default: "member", null: false, enum_type: "team_member_roles"
    t.uuid "team_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["team_id", "user_id"], name: "index_team_memberships_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "team_profiles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.uuid "team_id", null: false
    t.datetime "updated_at", null: false
    t.string "website_url"
    t.index ["team_id"], name: "index_team_profiles_on_team_id"
  end

  create_table "teams", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "inherit_parent_memberships", default: true, null: false
    t.string "name", null: false
    t.uuid "parent_id"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["parent_id"], name: "index_teams_on_parent_id"
  end

  create_table "test", id: false, force: :cascade do |t|
    t.uuid "application_id"
    t.string "client_id"
    t.string "client_secret"
    t.boolean "confidential"
    t.datetime "created_at"
    t.boolean "enabled"
    t.datetime "expires_at"
    t.string "grant_flows", array: true
    t.uuid "id"
    t.string "name"
    t.string "redirect_uris", array: true
    t.string "scopes", array: true
    t.datetime "updated_at"
  end

  create_table "user_profiles", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "display_name", limit: 64, null: false
    t.jsonb "preferences", default: {}
    t.uuid "user_id", null: false
    t.index ["preferences"], name: "index_user_profiles_on_preferences", using: :gin
    t.index ["user_id"], name: "index_user_profiles_on_user_id", unique: true
  end

  create_table "user_social_identities", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.string "access_token"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.string "nickname"
    t.string "provider", null: false
    t.json "raw_info"
    t.string "refresh_token"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["provider", "external_id"], name: "index_user_social_identities_on_provider_and_external_id", unique: true
    t.index ["user_id"], name: "index_user_social_identities_on_user_id"
  end

  create_table "user_totp_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.decimal "consumed_timestep"
    t.datetime "created_at", null: false
    t.string "otp_backup_codes", array: true
    t.boolean "otp_enabled", default: false
    t.string "otp_secret", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_user_totp_credentials_on_user_id", unique: true
  end

  create_table "user_webauthn_credentials", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.uuid "aaguid"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname", null: false
    t.string "public_key", null: false
    t.jsonb "raw_data"
    t.boolean "resident_key", default: false, null: false
    t.integer "sign_count", default: 0, null: false
    t.string "transports", array: true
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["external_id"], name: "index_user_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id", "nickname"], name: "index_user_webauthn_credentials_on_user_id_and_nickname", unique: true
    t.index ["user_id"], name: "index_user_webauthn_credentials_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.enum "roles", default: [], null: false, array: true, enum_type: "user_roles"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.string "webauthn_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "webauthn_device_classes", id: :uuid, default: -> { "uuidv7()" }, force: :cascade do |t|
    t.text "icon_dark"
    t.text "icon_light"
    t.boolean "manual", default: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "character_registrations", "ffxiv_characters", column: "character_id"
  add_foreign_key "client_application_access_control_lists", "client_applications", column: "application_id"
  add_foreign_key "client_application_oauth_clients", "client_applications", column: "application_id"
  add_foreign_key "client_application_obo_authorizations", "client_applications", column: "audience_id"
  add_foreign_key "client_application_obo_authorizations", "client_applications", column: "authorized_party_id"
  add_foreign_key "client_application_profiles", "client_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "client_application_oauth_clients", column: "application_id"
  add_foreign_key "oauth_access_grants", "oauth_permissible_policies", column: "permissible_policy_id"
  add_foreign_key "oauth_access_tokens", "client_application_oauth_clients", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_permissible_policies", column: "permissible_policy_id"
  add_foreign_key "oauth_device_grants", "client_application_oauth_clients", column: "application_id"
  add_foreign_key "oauth_device_grants", "oauth_permissible_policies", column: "permissible_policy_id"
  add_foreign_key "oauth_permissible_rules", "oauth_permissible_policies", column: "policy_id"
  add_foreign_key "pki_issued_certificates", "pki_certificate_authorities", column: "certificate_authority_id"
  add_foreign_key "team_invite_links", "teams", on_delete: :cascade
  add_foreign_key "team_memberships", "teams", on_delete: :cascade
  add_foreign_key "team_memberships", "users", on_delete: :cascade
  add_foreign_key "team_profiles", "teams", on_delete: :cascade
  add_foreign_key "teams", "teams", column: "parent_id", on_delete: :cascade
  add_foreign_key "user_profiles", "users"
  add_foreign_key "user_social_identities", "users"
  add_foreign_key "user_totp_credentials", "users"
  add_foreign_key "user_webauthn_credentials", "users"
end
