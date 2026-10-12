# Policy object describing how one kind of uploaded file is validated, processed,
# and stored. Declared on models via has_upload_attachment(strategy:) and
# dispatched to by AttachmentUploader, which holds no policy of its own.
#
# The class is the kind of file (image, document); the constructor arguments are
# the per-declaration tuning (which types, what limit, which extra checks).
#
# This class is usable on its own: it stores whatever it is given, unprocessed,
# subject to the generic constraints below. Subclasses add processing and narrow
# what they are willing to accept.
#
#   has_upload_attachment :export,
#                         strategy: UploadStrategy.new(content_types: %w[application/zip],
#                                                      max_size: 10.megabytes),
#                         validate: MalwareScan
class UploadStrategy
  # MIME types this kind of strategy is capable of handling at all. nil means it
  # imposes no restriction of its own, and the declaration must say what it
  # accepts. Subclasses that only understand certain formats override this; a
  # declaration may then narrow that list, but never widen it.
  class_attribute :supported_types, instance_writer: false, default: nil

  attr_reader :content_types, :max_size, :validators

  # content_types: Permitted MIME types. Required when the strategy declares no
  #                supported_types of its own, so a passthrough strategy can
  #                never silently accept anything.
  # max_size:      Maximum size in bytes.
  # validators:    Extra checks, as callables taking the Shrine attacher and
  #                pushing onto its +errors+. Run once the generic constraints
  #                pass, so an already-rejected file never reaches something
  #                expensive. Use these for rules that belong to this strategy
  #                instance.
  # derivatives:   { name => callable }, each taking (original, attacher) and
  #                returning a processed file. Subclasses may accept richer specs.
  def initialize(content_types: supported_types, max_size: 10.megabytes, validators: [], derivatives: { })
    raise ArgumentError, "#{self.class.name} accepts any file; declare content_types" if content_types.nil?

    @content_types = Array(content_types).map(&:to_s).freeze
    @max_size      = max_size
    @validators    = Array(validators).freeze
    @derivatives   = derivatives.freeze

    return if supported_types.nil?

    unsupported = @content_types - supported_types
    return if unsupported.empty?

    raise ArgumentError, "#{self.class.name} cannot handle #{unsupported.join(', ')}"
  end

  # Runs during Shrine's validation phase. Subclasses hook in via
  # #validate_content rather than overriding this, so the generic constraints
  # can never be skipped by forgetting to call super.
  def validate(attacher)
    attacher.validate_mime_type content_types
    attacher.validate_max_size  max_size
    return if attacher.errors.any?

    validate_content(attacher)
    validators.each { |validator| validator.call(attacher) }
  end

  # Format-specific validation. Called only once the generic constraints pass.
  def validate_content(_attacher); end

  # The derivative names this strategy produces, knowable without doing any work.
  def derivative_names = @derivatives.keys

  # Returns { derivative_name => processed_file } for the promoted original.
  def derivatives(original, attacher)
    @derivatives.transform_values do |spec|
      raise ArgumentError, "unknown derivative spec #{spec.inspect}" unless spec.respond_to?(:call)

      spec.call(original, attacher)
    end
  end

  # Returns the IO to promote to permanent storage. Defaults to storing exactly
  # what was uploaded; override to sanitize or normalize the original.
  def process_original(io, _attacher)
    io
  end

  # Storage-level options applied when promoting, e.g. content disposition.
  def upload_options(_attacher)
    { }
  end
end
