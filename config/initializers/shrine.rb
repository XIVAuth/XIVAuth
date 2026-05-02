require "shrine"
require "shrine/storage/memory"

if Rails.env.test?

  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::Memory.new
  }
elsif Rails.application.credentials.dig(:storage, :uploads, :bucket)
  require "shrine/storage/s3"

  def self.s3_storage_from_credentials(key)
    creds = Rails.application.credentials.dig(:storage, key)
    Shrine::Storage::S3.new(
      bucket:            creds[:bucket],
      region:            "auto",
      access_key_id:     creds[:access_key_id],
      secret_access_key: creds[:secret_access_key],
      endpoint:          creds[:endpoint],
      prefix:            creds[:prefix],
      force_path_style:  true,
      copy_options:      {}
    )
  end

  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: s3_storage_from_credentials(:uploads)
  }

  Shrine.plugin :url_options, store: { host: "https://cdn.xivauth.net" }
else
  require "shrine/storage/file_system"

  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::FileSystem.new("storage", prefix: "uploads")
  }
end

Shrine.plugin :activerecord
Shrine.plugin :cached_attachment_data
Shrine.plugin :determine_mime_type, analyzer: :marcel
Shrine.plugin :validation
Shrine.plugin :validation_helpers
Shrine.plugin :derivatives
