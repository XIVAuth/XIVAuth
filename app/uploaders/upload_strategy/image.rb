class UploadStrategy::Image < UploadStrategy
  self.supported_types = %w[image/png image/jpeg image/webp image/gif].freeze

  # Uploaded type => the format the stored original is re-encoded to when it has
  # to be rewritten. GIF is conditional: re-encoding one would flatten animation,
  # so it is only safe when animated uploads are rejected outright.
  REENCODE_FORMATS = { "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp" }.freeze
  ANIMATABLE_FORMATS = { "image/gif" => "gif" }.freeze

  # Formats capable of carrying more than one frame.
  ANIMATED_TYPES = %w[image/gif image/webp image/png image/apng].freeze

  # Re-encoding the original to strip metadata is lossy for JPEG, so it is done
  # at a higher quality than the derivative default.
  ORIGINAL_QUALITY = 90

  attr_reader :format, :quality, :transform

  # derivatives: { name => spec }, where a spec is one of:
  #          [width, height] or [width, height, :fill | :fit | :limit] — resize,
  #            defaulting to :fill (crops to exactly those dimensions);
  #          { size: [w, h], fit: :limit, transform: callable } — as above, with a
  #            transform applied to this derivative alone;
  #          a callable taking the configured pipeline and returning a processed
  #            file — the escape hatch, for anything the declarative forms can't say.
  # format:  Convert derivatives to this format, e.g. "webp". The stored original
  #          always keeps the format it was uploaded in.
  # saver:   Extra format-specific saver options for derivatives, e.g.
  #          near_lossless:. image_processing drops options that are invalid for
  #          the format being written, so these are safe to set broadly.
  # quality: Saver quality for derivatives. Defaults to libvips' own default.
  # transform: Callable taking a pipeline and returning a pipeline, e.g.
  #          ->(pipeline) { pipeline.colourspace("b-w") }. Applies to the stored
  #          original only, during the same re-encode that strips metadata — it
  #          composes with stripping rather than replacing it, and forces the
  #          re-encode even when strip_metadata is false.
  #
  #          Derivatives are generated from the stored original, so they inherit
  #          it for free. A derivative that needs something further declares its
  #          own transform in its spec, which stacks on top.
  #
  #          Skipped for formats that cannot be re-encoded safely (see
  #          #reencode_target) — today, GIF when allow_animation: true.
  # strip_metadata:  Re-encode the stored original without EXIF/XMP/ICC. On by
  #          default, since originals are served from a public CDN.
  # allow_animation: Permit multi-frame uploads.
  def initialize(derivatives: { }, format: nil, saver: { }, quality: nil, transform: nil,
                 strip_metadata: true, allow_animation: false, max_size: 2.megabytes, **)
    super(derivatives: derivatives, max_size: max_size, **)

    @transform       = transform
    @format          = format
    @saver           = saver.freeze
    @quality         = quality
    @strip_metadata  = strip_metadata
    @allow_animation = allow_animation
  end

  def strip_metadata? = @strip_metadata

  def allow_animation? = @allow_animation

  def validate_content(attacher)
    validate_not_animated(attacher) unless allow_animation?
  end

  # The pipeline a callable derivative spec receives: format, saver and quality
  # already applied. The strategy's transform is not — the stored original this
  # reads from already carries it.
  def pipeline(original)
    pipeline = ImageProcessing::Vips.source(original)
    pipeline = pipeline.convert(format) if format
    pipeline.saver(**derivative_saver_options)
  end

  def derivatives(original, _attacher)
    configured = pipeline(original)

    @derivatives.transform_values { |spec| build(configured, spec) }
  end

  # Rewrites the stored original through libvips, discarding metadata and
  # applying any original-side transform in the same pass. Returns the file
  # untouched when there is nothing to do, or when the format can't be re-encoded
  # safely.
  def process_original(io, _attacher)
    target = reencode_target(io.mime_type)
    return io unless target && (strip_metadata? || transform)

    io.download do |tempfile|
      pipeline = ImageProcessing::Vips.source(tempfile).convert(target)
      pipeline = transform.call(pipeline) if transform
      pipeline.saver(strip: strip_metadata?, quality: quality || ORIGINAL_QUALITY).call
    end
  end

  private def reencode_target(mime_type)
    return ANIMATABLE_FORMATS[mime_type] if !allow_animation? && ANIMATABLE_FORMATS.key?(mime_type)

    REENCODE_FORMATS[mime_type]
  end

  private def build(pipeline, spec)
    return spec.call(pipeline) if spec.respond_to?(:call)

    case spec
    when Array
      width, height, fit = spec
      resize(pipeline, width, height, fit || :fill)
    when Hash
      width, height = spec.fetch(:size)
      stage = spec[:transform] ? spec[:transform].call(pipeline) : pipeline
      resize(stage, width, height, spec.fetch(:fit, :fill))
    else
      raise ArgumentError, "unknown derivative spec #{spec.inspect}"
    end
  end

  private def resize(pipeline, width, height, mode)
    case mode
    when nil, :fill then pipeline.resize_to_fill!(width, height)
    when :fit       then pipeline.resize_to_fit!(width, height)
    when :limit     then pipeline.resize_to_limit!(width, height)
    else raise ArgumentError, "unknown resize mode #{mode.inspect}"
    end
  end

  private def derivative_saver_options
    options = { strip: strip_metadata? }.merge(@saver)
    options[:quality] = quality if quality
    options
  end

  private def validate_not_animated(attacher)
    file = attacher.file
    return unless file && ANIMATED_TYPES.include?(file.mime_type)
    return unless file.open { |io| self.class.animated?(io) }

    attacher.errors << "must not be animated."
  end

  def self.animated?(io)
    Vips::Image.new_from_buffer(io.read, "").get("n-pages") > 1
  rescue Vips::Error
    false
  end
end
