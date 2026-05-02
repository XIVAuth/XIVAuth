module HasUploadAttachment
  extend ActiveSupport::Concern

  included do
    has_many :attachments, as: :record, class_name: "Attachment",
             dependent: :destroy, autosave: true

    before_save :destroy_replaced_attachments
    validate :propagate_attachment_errors
  end

  private

  def propagate_attachment_errors
    attachments.each do |attachment|
      next if attachment.valid?

      attachment.errors.each do |error|
        errors.add(attachment.name.to_sym, error.message)
      end
    end
  end

  def destroy_replaced_attachments
    (@_attachments_to_replace || []).each(&:destroy)
    @_attachments_to_replace = nil
  end

  class_methods do
    # Declares a single-file attachment. The setter replaces any existing
    # attachment with the same name; the getter returns one Attachment or nil.
    #
    # Options:
    #   prefix:        Override the storage path prefix (String or Proc). The storage's
    #                  own prefix is always preserved — this sits after it. Defaults to
    #                  "<model_plural>/<record_id>/<name>". A Proc receives the owner
    #                  record as its argument.
    #   content_types: Array of permitted MIME types, e.g. %w[image/png image/jpeg].
    #   max_size:      Maximum file size in bytes, e.g. 2.megabytes.
    #   validate:      Proc (or array of procs) run in Shrine attacher context for
    #                  arbitrary validation. Has access to +file+, +record+, +errors+,
    #                  and all Shrine validation helpers.
    def has_upload_attachment(name, prefix: nil, content_types: nil, max_size: nil, validate: nil)
      _register_upload_attachment(name, prefix: prefix, content_types: content_types,
                                        max_size: max_size, validate: validate)

      define_method(name) do
        if attachments.loaded?
          attachments.find { |a| a.name == name.to_s }
        else
          attachments.find_by(name: name.to_s)
        end
      end

      define_method(:"#{name}=") do |file|
        return if file.blank? || file.respond_to?(:original_filename) && file.original_filename.blank?

        incoming_sha256 = Digest::SHA256.hexdigest(file.read).tap { file.rewind }
        old = attachments.find_by(name: name.to_s)
        return if old&.sha256 == incoming_sha256

        if old
          @_attachments_to_replace ||= []
          @_attachments_to_replace << old
          attachments.target.delete(old)
        end
        attachment = attachments.build(name: name.to_s, sha256: incoming_sha256)
        attachment.file = file
      end
    end

    # Declares a multi-file attachment. The getter returns a scoped collection;
    # use build_<singular> to append a new file.
    #
    # Accepts the same options as has_upload_attachment.
    def has_upload_attachments(name, prefix: nil, content_types: nil, max_size: nil, validate: nil)
      _register_upload_attachment(name, prefix: prefix, content_types: content_types,
                                        max_size: max_size, validate: validate, multiple: true)

      define_method(name) do
        attachments.where(name: name.to_s)
      end

      singular = name.to_s.singularize
      define_method(:"build_#{singular}") do |file|
        attachment = attachments.build(name: name.to_s)
        attachment.file = file
        attachment
      end
    end

    def upload_attachment_configs
      base = superclass.respond_to?(:upload_attachment_configs) ? superclass.upload_attachment_configs : {}
      base.merge(@upload_attachment_configs ||= {})
    end

    private

    def _register_upload_attachment(name, **options)
      @upload_attachment_configs ||= {}
      @upload_attachment_configs[name.to_sym] = options
    end
  end
end
