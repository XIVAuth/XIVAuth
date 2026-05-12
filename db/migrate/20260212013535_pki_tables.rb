class PKITables < ActiveRecord::Migration[8.1]
  def up
    create_enum :pki_subject_type, %w[user character_registration]

    # RFC 5280 CRLReason values
    # removeFromCRL is intentionally not included as it's a logical value and won't be stored in the DB.
    create_enum :pki_revocation_reason, %w[
      unspecified key_compromise ca_compromise affiliation_changed
      superseded cessation_of_operation certificate_hold
      privilege_withdrawn aa_compromise
    ]

    create_table :pki_certificate_authorities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :slug,            null: false, index: { unique: true }
      t.text    :certificate_pem, null: false  # file, strictly.
      t.text    :private_key,     null: false  # encrypted via ActiveRecord
      t.boolean :active,          null: false, default: true, index: true

      t.enum    :allowed_subject_types, enum_type: :pki_subject_type,
                array: true, null: false, default: %w[user character_registration]

      t.string  :certificate_fingerprint, null: false, index: { unique: true }
      t.string  :public_key_fingerprint,  null: false, index: true

      t.datetime :expires_at

      t.datetime :revoked_at
      t.enum :revocation_reason, enum_type: :pki_revocation_reason, null: true
      t.timestamps
    end

    create_table :pki_issued_certificates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :certificate_authority, type: :uuid, null: false,
                   foreign_key: { to_table: :pki_certificate_authorities }

      # NOTE: references intentionally don't have foreign keys, since we can't guarantee the other side
      # will always exist, and this table will also act as an audit log.
      t.references :requesting_application, type: :uuid, null: true, foreign_key: false, index: true
      t.references :subject, type: :uuid, polymorphic: true, index: true

      t.text :certificate_pem, null: false

      t.datetime :issued_at,  null: false
      t.datetime :expires_at, null: false

      # Structured public key metadata:
      # RSA: { "type" => "RSA", "bits" => 4096 }
      # EC:  { "type" => "EC",  "curve" => "prime256v1", "bits" => 256 }
      t.jsonb  :public_key_info,    null: false, default: { }
      t.jsonb  :issuance_context,   null: false, default: { }

      t.string :public_key_fingerprint, null: false, index: true
      t.string :certificate_fingerprint, null: false, index: { unique: true }

      t.datetime :revoked_at
      t.enum :revocation_reason, enum_type: :pki_revocation_reason, null: true
      t.timestamps
    end
  end

  def down
    drop_table :pki_issued_certificates
    drop_table :pki_certificate_authorities
    drop_enum :pki_revocation_reason
    drop_enum :pki_subject_type
  end
end
