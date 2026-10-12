require "rails_helper"

RSpec.describe UploadStrategy do
  # The base strategy stores whatever it is handed, so it is exercised with a
  # file it does no processing for at all.
  let(:pdf_bytes) { "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n%%EOF\n" }

  def upload(bytes, mime, filename = "file.bin")
    attacher = AttachmentUploader::Attacher.new
    attacher.assign(Rack::Test::UploadedFile.new(StringIO.new(bytes), mime, original_filename: filename))
    attacher
  end

  def errors_from(strategy, attacher)
    strategy.validate(attacher)
    attacher.errors
  end

  describe "declaration" do
    it "requires content_types, since it would otherwise accept anything" do
      expect { described_class.new }
        .to raise_error(ArgumentError, /accepts any file; declare content_types/)
    end

    it "accepts any declared type, having no format restriction of its own" do
      strategy = described_class.new(content_types: %w[application/pdf application/zip])

      expect(errors_from(strategy, upload(pdf_bytes, "application/pdf", "doc.pdf"))).to be_empty
    end

    it "defaults to a 10MB limit" do
      expect(described_class.new(content_types: %w[application/pdf]).max_size).to eq(10.megabytes)
    end
  end

  describe "generic constraints" do
    it "rejects a type outside the declared list" do
      strategy = described_class.new(content_types: %w[application/zip])

      expect(errors_from(strategy, upload(pdf_bytes, "application/pdf", "doc.pdf")))
        .to include(/type must be one of/)
    end

    it "rejects a file over the size limit" do
      strategy = described_class.new(content_types: %w[application/pdf], max_size: 10)

      expect(errors_from(strategy, upload(pdf_bytes, "application/pdf", "doc.pdf")))
        .to include(/size must not be greater/)
    end
  end

  describe "validators:" do
    let(:rejector) { ->(attacher) { attacher.errors << "failed the scan." } }

    it "runs checks carried by the strategy instance" do
      strategy = described_class.new(content_types: %w[application/pdf], validators: [rejector])

      expect(errors_from(strategy, upload(pdf_bytes, "application/pdf", "doc.pdf")))
        .to include("failed the scan.")
    end

    it "accepts a single callable" do
      expect(described_class.new(content_types: %w[application/pdf], validators: rejector).validators)
        .to eq([rejector])
    end

    it "skips them when the generic constraints already failed" do
      strategy = described_class.new(content_types: %w[application/zip], validators: [rejector])

      expect(errors_from(strategy, upload(pdf_bytes, "application/pdf", "doc.pdf")))
        .not_to include("failed the scan.")
    end

    it "runs alongside a subclass's own validation" do
      square = ->(attacher) { attacher.errors << "must be square." }
      strategy = UploadStrategy::Image.new(validators: [square])
      png = Vips::Image.black(40, 20).add(200).cast("uchar").write_to_buffer(".png")

      expect(errors_from(strategy, upload(png, "image/png", "x.png"))).to include("must be square.")
    end
  end

  describe "derivatives:" do
    let(:attacher) { upload(pdf_bytes, "application/pdf", "doc.pdf") }

    it "runs callables taking the original and the attacher" do
      strategy = described_class.new(content_types: %w[application/pdf],
                                     derivatives: { manifest: ->(original, _a) { StringIO.new(original.size.to_s) } })

      expect(strategy.derivatives(StringIO.new("0123456789"), attacher)[:manifest].read).to eq("10")
    end

    it "exposes the names it will produce without doing any work" do
      strategy = described_class.new(content_types: %w[application/pdf],
                                     derivatives: { manifest: ->(_o, _a) { raise "never called" } })

      expect(strategy.derivative_names).to eq([:manifest])
    end

    it "rejects a spec that is not callable" do
      strategy = described_class.new(content_types: %w[application/pdf], derivatives: { bad: [1, 2] })

      expect { strategy.derivatives(nil, attacher) }.to raise_error(ArgumentError, /unknown derivative spec/)
    end
  end

  describe "passthrough behaviour" do
    let(:strategy) { described_class.new(content_types: %w[application/pdf]) }
    let(:attacher) { upload(pdf_bytes, "application/pdf", "doc.pdf") }

    it "stores the original untouched" do
      expect(strategy.process_original(attacher.file, attacher)).to equal(attacher.file)
    end

    it "generates no derivatives when none are declared" do
      expect(strategy.derivatives(nil, attacher)).to eq({ })
    end

    it "adds no storage options" do
      expect(strategy.upload_options(attacher)).to eq({ })
    end
  end
end
