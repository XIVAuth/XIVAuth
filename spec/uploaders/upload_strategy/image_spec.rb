require "rails_helper"

RSpec.describe UploadStrategy::Image do
  # Fixtures are generated rather than checked in so the EXIF payload under test
  # is unambiguous, and so animated cases only run where libvips can write them.
  def solid(width: 40, height: 40, value: 120, ext: ".jpg")
    band = Vips::Image.black(width, height).add(value).cast("uchar")
    band.bandjoin([band, band]).copy(interpretation: :srgb).write_to_buffer(ext)
  end

  def jpeg_with_exif
    band = Vips::Image.black(300, 200).add(120).cast("uchar")
    band.bandjoin([band, band]).copy(interpretation: :srgb)
        .mutate { |m| m.set_type!(GObject::GSTR_TYPE, "exif-ifd0-ImageDescription", "SECRET-LOCATION") }
        .write_to_buffer(".jpg")
  end

  def animated(ext)
    a = Vips::Image.black(8, 8).add(200).cast("uchar")
    b = Vips::Image.black(8, 8).add(20).cast("uchar")
    Vips::Image.arrayjoin([a, b], across: 1).copy
               .mutate { |m| m.set_type!(GObject::GINT_TYPE, "page-height", 8) }
               .write_to_buffer(ext)
  end

  def exif_fields(bytes) = Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/exif/)

  def dimensions(file)
    image = Vips::Image.new_from_buffer(file.read.tap { file.rewind }, "")
    [image.width, image.height]
  end

  def upload(bytes, mime, filename = "file.img")
    attacher = AttachmentUploader::Attacher.new
    attacher.assign(Rack::Test::UploadedFile.new(StringIO.new(bytes), mime, original_filename: filename))
    attacher
  end

  def errors_from(strategy, attacher)
    strategy.validate(attacher)
    attacher.errors
  end

  describe "declaration" do
    it "rejects content types the strategy cannot handle" do
      expect { described_class.new(content_types: %w[application/pdf]) }
        .to raise_error(ArgumentError, %r{cannot handle application/pdf})
    end

    it "defaults to every supported image type" do
      expect(described_class.new.content_types).to match_array(described_class.supported_types)
    end

    it "exposes its configuration without needing an attacher" do
      strategy = described_class.new(max_size: 5.megabytes)

      expect(strategy.max_size).to eq(5.megabytes)
      expect(strategy).to be_strip_metadata
    end
  end

  describe "#validate" do
    it "accepts a permitted type within the size limit" do
      expect(errors_from(described_class.new, upload(solid, "image/jpeg"))).to be_empty
    end

    it "rejects a type outside the declared list" do
      strategy = described_class.new(content_types: %w[image/png])

      expect(errors_from(strategy, upload(solid, "image/jpeg"))).to include(/type must be one of/)
    end

    it "rejects a file over the size limit" do
      strategy = described_class.new(max_size: 10)

      expect(errors_from(strategy, upload(solid, "image/jpeg"))).to include(/size must not be greater/)
    end

    %w[gif webp].each do |fmt|
      next if Vips.type_find("VipsOperation", "#{fmt}save").zero?

      it "rejects an animated #{fmt} by default" do
        expect(errors_from(described_class.new, upload(animated(".#{fmt}"), "image/#{fmt}")))
          .to include("must not be animated.")
      end

      it "accepts an animated #{fmt} when animation is allowed" do
        strategy = described_class.new(allow_animation: true)

        expect(errors_from(strategy, upload(animated(".#{fmt}"), "image/#{fmt}"))).to be_empty
      end
    end
  end

  describe "#process_original" do
    let(:attacher) { upload(jpeg_with_exif, "image/jpeg", "photo.jpg") }

    it "strips metadata from the stored original" do
      expect(exif_fields(attacher.file.read)).not_to be_empty
      attacher.file.close

      processed = described_class.new.process_original(attacher.file, attacher)

      expect(exif_fields(processed.read)).to be_empty
    end

    it "preserves the image itself" do
      processed = described_class.new.process_original(attacher.file, attacher)

      expect(dimensions(processed)).to eq([300, 200])
    end

    it "returns the file untouched when stripping is disabled" do
      strategy = described_class.new(strip_metadata: false)

      expect(strategy.process_original(attacher.file, attacher)).to equal(attacher.file)
    end

    it "leaves GIFs alone when animation is allowed, since a re-encode would flatten it" do
      gif = upload(Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), "image/gif")
      strategy = described_class.new(allow_animation: true)

      expect(strategy.process_original(gif.file, gif)).to equal(gif.file)
    end

    it "re-encodes GIFs when animation is rejected, so they are stripped like anything else" do
      gif = upload(Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), "image/gif")

      expect(described_class.new.process_original(gif.file, gif)).not_to equal(gif.file)
    end

    it "applies an original-side transform alongside stripping, not instead of it" do
      strategy = described_class.new(transform: ->(pipeline) { pipeline.colourspace("b-w") })
      bytes = strategy.process_original(attacher.file, attacher).read

      expect(Vips::Image.new_from_buffer(bytes, "").bands).to eq(1)
      expect(exif_fields(bytes)).to be_empty
    end

    it "rewrites the original for a transform even when stripping is off" do
      strategy = described_class.new(strip_metadata: false,
                                     transform: ->(pipeline) { pipeline.colourspace("b-w") })
      processed = strategy.process_original(attacher.file, attacher)

      expect(Vips::Image.new_from_buffer(processed.read, "").bands).to eq(1)
    end

    it "leaves the original alone when only a derivative declares a transform" do
      strategy = described_class.new(
        strip_metadata: false,
        derivatives: { a: { size: [32, 32], transform: ->(p) { p.colourspace("b-w") } } }
      )

      expect(strategy.process_original(attacher.file, attacher)).to equal(attacher.file)
    end
  end

  describe "#derivatives" do
    let(:attacher) { upload(solid(width: 4000, height: 1000), "image/jpeg") }

    def derive(strategy, from: attacher)
      from.file.download { |original| strategy.derivatives(original, from) }
    end

    it "crops to exact dimensions by default" do
      expect(dimensions(derive(described_class.new(derivatives: { large: [256, 256] }))[:large])).to eq([256, 256])
    end

    it "scales without cropping for :limit" do
      expect(dimensions(derive(described_class.new(derivatives: { hd: [2560, 1440, :limit] }))[:hd])).to eq([2560, 640])
    end

    it "converts to the declared format" do
      hd = derive(described_class.new(format: "webp", derivatives: { hd: [100, 100] }))[:hd]
      loader = Vips::Image.new_from_buffer(hd.read, "").get("vips-loader")

      expect(loader).to start_with("webpload")
    end

    it "strips metadata from derivatives" do
      source = upload(jpeg_with_exif, "image/jpeg")
      large = derive(described_class.new(derivatives: { large: [64, 64] }), from: source)[:large]

      expect(exif_fields(large.read)).to be_empty
    end

    it "leaves the derivative pipeline alone, since the stored original already carries the transform" do
      strategy = described_class.new(derivatives: { a: [32, 32] },
                                     transform: ->(pipeline) { pipeline.colourspace("b-w") })

      expect(Vips::Image.new_from_buffer(derive(strategy)[:a].read, "").bands).to eq(3)
    end

    it "applies a per-derivative transform to that derivative alone" do
      strategy = described_class.new(
        derivatives: {
          colour: [32, 32],
          mono: { size: [32, 32], transform: ->(pipeline) { pipeline.colourspace("b-w") } }
        }
      )
      derived = derive(strategy)

      expect(Vips::Image.new_from_buffer(derived[:mono].read, "").bands).to eq(1)
      expect(Vips::Image.new_from_buffer(derived[:colour].read, "").bands).to eq(3)
    end

    it "honours fit in the hash form" do
      strategy = described_class.new(derivatives: { hd: { size: [2560, 1440], fit: :limit } })

      expect(dimensions(derive(strategy)[:hd])).to eq([2560, 640])
    end

    it "accepts a callable spec, for anything the declarative forms can't express" do
      strategy = described_class.new(derivatives: {
        odd: ->(pipeline) { pipeline.colourspace("b-w").resize_to_fill!(24, 24) }
      })
      odd = Vips::Image.new_from_buffer(derive(strategy)[:odd].read, "")

      expect([odd.width, odd.height, odd.bands]).to eq([24, 24, 1])
    end

    it "applies the strategy's format and saver settings to a callable spec" do
      strategy = described_class.new(format: "webp", derivatives: {
        odd: ->(pipeline) { pipeline.resize_to_fill!(24, 24) }
      })
      loader = Vips::Image.new_from_buffer(derive(strategy)[:odd].read, "").get("vips-loader")

      expect(loader).to start_with("webpload")
    end

    it "exposes its derivative names without running libvips" do
      expect(described_class.new(derivatives: { a: [1, 1], b: ->(p) { p } }).derivative_names)
        .to eq(%i[a b])
    end

    it "raises on an unrecognised derivative spec" do
      expect { derive(described_class.new(derivatives: { odd: "256x256" })) }
        .to raise_error(ArgumentError, /unknown derivative spec/)
    end

    it "raises on an unknown resize mode" do
      expect { derive(described_class.new(derivatives: { odd: [10, 10, :squish] })) }
        .to raise_error(ArgumentError, /unknown resize mode/)
    end
  end
end
