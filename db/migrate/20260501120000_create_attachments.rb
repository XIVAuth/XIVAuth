class CreateAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :attachments, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name,        null: false
      t.string :record_type, null: false
      t.uuid   :record_id,   null: false
      t.jsonb  :file_data

      t.timestamps
    end

    add_index :attachments, [:record_type, :record_id, :name]
  end
end
