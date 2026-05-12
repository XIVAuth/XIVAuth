namespace :pki do
  desc "Generate a self-signed development CA and load it into the database"
  task generate_ca: :environment do
    slug = ENV.fetch("SLUG", "xivauth-dev-#{Time.current.year}")
    cn   = ENV.fetch("CN",   "XIVAuth Dev CA #{Time.current.year}")

    abort "A CA with slug '#{slug}' already exists." if PKI::CertificateAuthority.exists?(slug: slug)

    puts "Generating CA key (this may take a moment)..."
    key = OpenSSL::PKey::EC.generate("prime256v1")

    puts "Building self-signed CA certificate..."
    cert = OpenSSL::X509::Certificate.new
    cert.serial     = 1
    cert.subject    = OpenSSL::X509::Name.parse("CN=#{cn}")
    cert.issuer     = cert.subject
    cert.public_key = key
    cert.not_before = Time.now.utc
    cert.not_after  = Time.now.utc + 10.years

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate  = cert
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(ef.create_extension("keyUsage", "keyCertSign,cRLSign", true))
    cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash"))

    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    ca = PKI::CertificateAuthority.create!(
      slug:            slug,
      certificate_pem: cert.to_pem,
      private_key:     key.to_pem,
      active:          true,
      allowed_certificate_types: PKI::IssuancePolicy.registry.keys
    )

    puts "Created PKI::CertificateAuthority:"
    puts "  id:   #{ca.id}"
    puts "  slug: #{ca.slug}"
    puts "  CN:   #{cn}"
    puts "  expires: #{ca.expires_at}"
    puts
    puts "CA certificate (PEM):"
    puts cert.to_pem
  end

  desc "Import an existing CA key and certificate into the database"
  task import_ca: :environment do
    slug = ENV.fetch("SLUG") { abort "SLUG env var required" }
    cert_file = ENV.fetch("CERT") { abort "CERT env var (path to PEM cert) required" }
    key_file  = ENV.fetch("KEY")  { abort "KEY env var (path to PEM key) required" }

    abort "A CA with slug '#{slug}' already exists." if PKI::CertificateAuthority.exists?(slug: slug)

    cert_pem = File.read(cert_file)
    key_pem  = File.read(key_file)

    # Verify the key matches the cert before importing.
    cert = OpenSSL::X509::Certificate.new(cert_pem)
    key  = OpenSSL::PKey.read(key_pem)
    unless cert.public_key.to_der == key.public_key.to_der
      abort "ERROR: private key does not match the certificate's public key."
    end

    ca = PKI::CertificateAuthority.create!(
      slug:            slug,
      certificate_pem: cert_pem,
      private_key:     key_pem,
      active:          true,
      expires_at:      cert.not_after
    )

    puts "Imported PKI::CertificateAuthority:"
    puts "  id:      #{ca.id}"
    puts "  slug:    #{ca.slug}"
    puts "  subject: #{cert.subject}"
    puts "  expires: #{ca.expires_at}"
  end
end
