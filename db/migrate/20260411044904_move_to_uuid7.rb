class MoveToUuid7 < ActiveRecord::Migration[8.1]
  def change
    change_column_default :character_bans,                          :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :character_registrations,                 :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :client_application_access_control_lists, :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :client_application_oauth_clients,        :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :client_application_profiles,             :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :client_applications,                     :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :ffxiv_characters,                        :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :jwt_signing_keys,                        :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :oauth_access_grants,                     :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :oauth_access_tokens,                     :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :oauth_device_grants,                     :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :oauth_permissible_policies,              :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :oauth_permissible_rules,                 :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :pki_certificate_authorities,             :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :pki_issued_certificates,                 :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :site_announcements,                      :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :team_invite_links,                       :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :team_memberships,                        :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :team_profiles,                           :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :teams,                                   :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :user_profiles,                           :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :user_social_identities,                  :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :user_totp_credentials,                   :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :user_webauthn_credentials,               :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :users,                                   :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
    change_column_default :webauthn_device_classes,                 :id, from: -> { "gen_random_uuid()" }, to: -> { "uuidv7()" }
  end
end
