require "rails_helper"

RSpec.describe AttachmentUploader do
  # Attachments are built rather than created: promotion and derivative
  # generation depend only on record_type/record_id, so the owning record never
  # has to exist (and the factories are unrelated to what's under test here).
  def jpeg_with_exif(width: 300, height: 200)
    band = Vips::Image.black(width, height).add(120).cast("uchar")
    band.bandjoin([band, band]).copy(interpretation: :srgb)
        .mutate { |m| m.set_type!(GObject::GSTR_TYPE, "exif-ifd0-ImageDescription", "SECRET-LOCATION") }
        .write_to_buffer(".jpg")
  end

  def attach(model, name, bytes, mime: "image/jpeg", filename: "photo.jpg")
    Attachment.new(record_type: model, record_id: SecureRandom.uuid, name: name.to_s).tap do |attachment|
      attachment.file = Rack::Test::UploadedFile.new(StringIO.new(bytes), mime, original_filename: filename)
    end
  end

  def exif_fields(bytes) = Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/exif/)

  def dimensions(bytes)
    image = Vips::Image.new_from_buffer(bytes, "")
    [image.width, image.height]
  end

  describe "promotion" do
    subject(:attachment) { attach("Team", :icon, jpeg_with_exif) }

    before { attachment.file_attacher.promote }

    it "stores an original with no embedded metadata" do
      expect(exif_fields(attachment.file.open(&:read))).to be_empty
    end

    it "stores an original that is still the uploaded image" do
      expect(dimensions(attachment.file.open(&:read))).to eq([300, 200])
    end

    it "carries filename and MIME type across the rewrite" do
      expect(attachment.file.mime_type).to eq("image/jpeg")
      expect(attachment.file.original_filename).to eq("photo.jpg")
    end

    it "keeps the declared storage prefix and extension" do
      expect(attachment.file.id).to start_with("teams/#{attachment.record_id}/icon/")
      expect(attachment.file.id).to end_with(".jpeg")
    end
  end

  describe "derivatives" do
    def derivatives_for(model, name, bytes, **)
      attach(model, name, bytes, **).tap do |attachment|
        attachment.file_attacher.promote
        attachment.file_attacher.create_derivatives
      end.file_attacher.derivatives
    end

    it "generates what Team#icon declares" do
      derivatives = derivatives_for("Team", :icon, jpeg_with_exif)

      expect(derivatives.keys).to eq([:large])
      expect(dimensions(derivatives[:large].read)).to eq([256, 256])
    end

    it "generates what User#avatar declares" do
      derivatives = derivatives_for("User", :avatar, jpeg_with_exif)

      expect(derivatives.keys).to match_array(%i[large medium])
      expect(dimensions(derivatives[:medium].read)).to eq([144, 144])
    end

    it "generates what ClientApplication#oauth_background declares" do
      derivatives = derivatives_for("ClientApplication", :oauth_background, jpeg_with_exif(width: 4000, height: 1000))

      expect(derivatives.keys).to match_array(%i[hd thumb])
      expect(dimensions(derivatives[:hd].read)).to eq([2560, 640])
      expect(dimensions(derivatives[:thumb].read)).to eq([160, 90])
    end
  end

  # Derivatives are generated from the stored original, so a transform placed on
  # the original is already present in every derivative. These go through the real
  # two-stage flow rather than calling the strategy directly, which is the only way
  # that interaction shows up.
  describe "transforms across promotion and derivative generation" do
    def solid_png(value)
      band = Vips::Image.black(100, 100).add(value).cast("uchar")
      band.bandjoin([band, band]).copy(interpretation: :srgb).write_to_buffer(".png")
    end

    def promote_with(strategy)
      attachment = attach("Team", :icon, solid_png(200), mime: "image/png", filename: "x.png")
      allow(attachment).to receive(:upload_strategy).and_return(strategy)
      attachment.file_attacher.promote
      attachment.file_attacher.create_derivatives

      [Vips::Image.new_from_buffer(attachment.file.open(&:read), "").avg.round,
       Vips::Image.new_from_buffer(attachment.file_attacher.derivatives[:a].read, "").avg.round]
    end

    let(:halve) { ->(pipeline) { pipeline.linear(0.5, 0).cast("uchar") } }

    it "applies the strategy's transform exactly once" do
      strategy = UploadStrategy::Image.new(derivatives: { a: [50, 50] }, transform: halve)

      expect(promote_with(strategy)).to eq([100, 100])
    end

    it "stacks a derivative's own transform on top of the original's" do
      strategy = UploadStrategy::Image.new(transform: halve,
                                           derivatives: { a: { size: [50, 50], transform: halve } })

      expect(promote_with(strategy)).to eq([100, 50])
    end

    it "leaves the original untouched when only a derivative declares a transform" do
      strategy = UploadStrategy::Image.new(strip_metadata: false,
                                           derivatives: { a: { size: [50, 50], transform: halve } })

      expect(promote_with(strategy)).to eq([200, 100])
    end
  end

  describe "validation" do
    it "applies the strategy declared on the owning model" do
      attachment = attach("ClientApplication", :oauth_background,
                          Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"),
                          mime: "image/gif", filename: "x.gif")
      attachment.valid?

      expect(attachment.errors[:file]).to include(/type must be one of/)
    end

    it "passes a file the strategy permits" do
      attachment = attach("ClientApplication", :oauth_background, jpeg_with_exif)
      attachment.valid?

      expect(attachment.errors[:file]).to be_empty
    end
  end
end
