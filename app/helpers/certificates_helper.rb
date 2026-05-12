module CertificatesHelper
  def format_fingerprint(fingerprint)
    fingerprint
      .sub(/^\w+:/, "")
      .scan(/.{4}/)
      .each_slice(8)
      .map { |g| g.join(" ") }
      .join("\n")
  end
end
