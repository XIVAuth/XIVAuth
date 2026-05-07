module ShrineValidations
  module AnimationDetector
    ANIMATED_MIME_TYPES = %w[image/gif image/webp image/png image/apng].freeze

    # Shrine attacher validation proc. Usage:
    #   has_upload_attachment :icon, validate: ShrineValidations::AnimationDetector::VALIDATE_NOT_ANIMATED
    VALIDATE_NOT_ANIMATED = lambda do
      next unless file

      animated = file.open { |io| ShrineValidations::AnimationDetector.animated?(io, file.mime_type) }
      errors << "must not be animated." if animated
    end

    def self.animated?(io, mime_type)
      return false unless ANIMATED_MIME_TYPES.include?(mime_type)

      image = Vips::Image.new_from_buffer(io.read, "")
      image.get("n-pages") > 1
    rescue Vips::Error
      false
    end
  end
end
