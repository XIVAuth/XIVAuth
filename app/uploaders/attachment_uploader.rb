class AttachmentUploader < Shrine
  Attacher.validate do
    config = record&.owner_attachment_config
    validate_mime_type config[:content_types] if config&.dig(:content_types)
    validate_max_size  config[:max_size]      if config&.dig(:max_size)

    Array(config[:validate]).each { |v| instance_exec(&v) }
  end

  def generate_location(io, record: nil, derivative: nil, metadata: {}, **)
    ext = File.extname(metadata["filename"].to_s).downcase

    if storage_key == :store && record&.record_id.present?
      owner_class = record.record_type.safe_constantize
      config      = owner_class&.upload_attachment_configs&.dig(record.name&.to_sym) || {}

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
