# Plumbing only: locations, promotion, and dispatch to the attachment's
# UploadStrategy. Everything that depends on what kind of file is being handled
# lives in the strategy, not here.
class AttachmentUploader < Shrine
  Attacher.derivatives do |original|
    record&.upload_strategy&.derivatives(original, self) || { }
  end

  Attacher.validate do
    record&.upload_strategy&.validate(self)
  end

  class Attacher < Shrine::Attacher
    # Lets the strategy rewrite the file on its way into permanent storage (e.g.
    # stripping image metadata). A rewritten file is an anonymous tempfile, so
    # the cached file's filename and MIME type are carried across explicitly --
    # generate_location depends on the latter for the stored extension.
    def promote(storage: store_key, **options)
      strategy = record&.upload_strategy
      return super if strategy.nil? || file.nil?

      processed      = strategy.process_original(file, self)
      upload_options = strategy.upload_options(self)

      options[:upload_options] = upload_options if upload_options.present?
      unless processed.equal?(file)
        options[:metadata] = { "filename" => file.original_filename, "mime_type" => file.mime_type }
      end

      set upload(processed, storage, action: :store, **options)
    end
  end

  def generate_location(_io, record: nil, derivative: nil, metadata: { }, **)
    ext = Rack::Mime::MIME_TYPES.key(metadata["mime_type"]) || File.extname(metadata["filename"].to_s).downcase

    if storage_key == :store && record&.record_id.present?
      owner_class = record.record_type.safe_constantize
      config      = owner_class&.upload_attachment_configs&.dig(record.name&.to_sym) || { }

      prefix = config[:prefix]
      prefix = prefix.call(record.record) if prefix.respond_to?(:call)
      prefix ||= "#{owner_class.model_name.plural}/#{record.record_id}/#{record.name}"

      # Derive the key from the cached file's basename so it's consistent
      # across the original upload and any derivatives generated later.
      key = File.basename(record.file.id, ".*")
      segment = derivative ? "#{key}_#{derivative}" : key
      "#{prefix}/#{segment}#{ext}"
    else
      # Path is relative to the cache storage's own prefix.
      SecureRandom.urlsafe_base64(24) + ext
    end
  end
end
