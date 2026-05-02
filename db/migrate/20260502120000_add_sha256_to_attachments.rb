class AddSha256ToAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :attachments, :sha256, :string, limit: 64
    add_index  :attachments, :sha256
  end
end
