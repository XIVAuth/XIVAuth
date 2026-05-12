module PkiSupport
  def self.shared_ecdsa_key(curve = "prime256v1")
    @shared_ecdsa_keys ||= { }
    @shared_ecdsa_keys[curve] ||= OpenSSL::PKey::EC.generate(curve)
  end

  def self.shared_rsa_key
    @shared_rsa_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def self.shared_ed25519_key
    @shared_ed25519_key ||= Ed25519::SigningKey.generate
  end

  def self.shared_ca_cert
    @shared_ca_cert ||=
      begin
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = 1
        cert.subject = OpenSSL::X509::Name.parse("CN=XIVAuth Test CA")
        cert.issuer = cert.subject
        cert.public_key = shared_ecdsa_key
        cert.not_before = Time.current - 1
        cert.not_after = 10.years.from_now

        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = cert
        ef.issuer_certificate = cert
        cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
        cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash"))
        # keyCertSign + cRLSign required for a conforming CA cert (RFC 5280 §4.2.1.3)
        cert.add_extension(ef.create_extension("keyUsage", "keyCertSign,cRLSign", true))

        cert.sign(shared_ecdsa_key, OpenSSL::Digest.new("SHA256"))
        cert
      end
  end

  # Generates a self-signed CA certificate for a given key.
  # Used when tests need a CA with a specific key type (e.g. RSA).
  def self.generate_ca_cert(key:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = SecureRandom.random_number(2 ** 64)
    cert.subject = OpenSSL::X509::Name.parse("CN=XIVAuth Test CA (#{key.class.name.split('::').last})")
    cert.issuer = cert.subject
    cert.public_key = key
    cert.not_before = 1.minute.ago
    cert.not_after = 10.years.from_now

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash"))
    cert.add_extension(ef.create_extension("keyUsage", "keyCertSign,cRLSign", true))

    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  # Generates a leaf certificate PEM signed by the shared test CA.
  # @param issuing_ca the issuing CA certificate
  # @param common_name [String] common name for the leaf cert
  # @param serial [Integer, nil] X.509 serial - defaults to a random UUID-derived integer
  # @param subject_key [OpenSSL::PKey] defaults to a fresh P-256 EC key
  def self.generate_leaf_pem(issuing_ca, issuing_ca_key, common_name: "Test Leaf", serial: nil, subject_key: nil)
    leaf_key = subject_key || OpenSSL::PKey::EC.generate("prime256v1")
    serial ||= SecureRandom.uuid.delete("-").to_i(16)

    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.new(serial.to_s)
    cert.subject = OpenSSL::X509::Name.parse("CN=#{common_name}")
    cert.issuer = issuing_ca.subject
    cert.public_key = leaf_key
    cert.not_before = Time.current - 30 # drift mitigation
    cert.not_after = 1.year.from_now

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuing_ca
    cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
    cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash"))
    cert.add_extension(ef.create_extension("authorityKeyIdentifier", "keyid:always"))
    key_usage = if leaf_key.is_a?(OpenSSL::PKey::RSA)
                  "digitalSignature,keyEncipherment"
                else
                  "digitalSignature,keyAgreement"
                end
    cert.add_extension(ef.create_extension("keyUsage", key_usage, true))

    cert.sign(issuing_ca_key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  # Returns a PEM-encoded CSR. Defaults to P-256 EC (fast); pass an RSA key to test RSA paths.
  def self.generate_csr_pem(key: nil)
    key ||= OpenSSL::PKey::EC.generate("prime256v1")
    req = OpenSSL::X509::Request.new
    req.version = 0
    req.subject = OpenSSL::X509::Name.parse("CN=Ignored By XIVAuth")
    req.public_key = key
    req.sign(key, OpenSSL::Digest.new("SHA256"))
    req.to_pem
  end
end
