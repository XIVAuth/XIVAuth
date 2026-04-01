require "resolv"

# Validate that an email address is (mostly) valid.
#
# Checks the email address against the `email_address` gem to validate compliance
# with whatever the RFC flavor of the month happens to be. If the email format
# is considered valid, attempt to do a DNS resolution to see if the user at least
# entered a valid domain (stops `gmail.ocm` and the like).
#
# Valid DNS resolutions are cached for 14 days, invalid resolutions are cached
# for however long the SOA says it should be.
class EmailValidator < ActiveModel::EachValidator
  DNS_TIMEOUT          = 0.2  # 200ms
  INVALID_TTL_FALLBACK = 5.minutes
  VALID_CACHE_TTL      = 14.days

  def validate_each(record, attribute, value)
    return if value.blank?

    addr = parse(value)

    unless addr&.valid?
      record.errors.add(attribute, options[:message] || :invalid)
      return
    end

    # Check if DNS. If not, we suspect the email to be in the correct format, but
    # not a DNS name. This is the MTA's problem now.
    dns_name = addr.host.dns_name
    return if dns_name.nil?

    return if reachable?(dns_name)

    record.errors.add(attribute, options[:message] || :unresolvable_domain)
  end

  private

  def parse(email)
    EmailAddress.new(email, host_validation: :syntax, host_allow_ip: true)
  rescue StandardError
    nil
  end

  def reachable?(dns_name)
    cached = Rails.cache.read(cache_key(dns_name))
    return cached unless cached.nil?

    result = query(dns_name)

    write_cache(dns_name, result) unless result.nil?

    result || result.nil?
  end

  # Returns true if the domain has MX or A records, false if we know this domain
  # can't get email, nil if we can't tell.
  def query(dns_name)
    Resolv::DNS.open do |dns|
      dns.timeouts = DNS_TIMEOUT
      return true if dns.getresources(dns_name, Resolv::DNS::Resource::IN::MX).any?
      return true if dns.getresources(dns_name, Resolv::DNS::Resource::IN::A).any?
      false
    end
  rescue Resolv::ResolvTimeout, Resolv::ResolvError, StandardError
    nil
  end

  def cache_key(dns_name)
    "email_domain_mx:#{dns_name.downcase}"
  end

  def write_cache(dns_name, valid)
    if valid
      Rails.cache.write(cache_key(dns_name), true, expires_in: VALID_CACHE_TTL)
    else
      Rails.cache.write(cache_key(dns_name), false, expires_in: negative_ttl(dns_name))
    end
  end

  # Returns the negative caching TTL for dns_name per RFC 2308:
  #   min(SOA TTL, SOA RDATA minimum field)
  # Walks up the domain tree until an authoritative SOA is found.
  # Falls back to INVALID_TTL_FALLBACK if no SOA is found or the query fails.
  def negative_ttl(dns_name)
    labels = Resolv::DNS::Name.create(dns_name).to_a
    Resolv::DNS.open do |dns|
      dns.timeouts = DNS_TIMEOUT
      labels.length.downto(2) do |n|
        name = Resolv::DNS::Name.new(labels.last(n))
        soa = dns.getresources(name, Resolv::DNS::Resource::IN::SOA).first
        return [ soa.ttl, soa.minimum ].min.seconds if soa
      end
    end
    INVALID_TTL_FALLBACK
  rescue Resolv::ResolvTimeout, Resolv::ResolvError, StandardError
    INVALID_TTL_FALLBACK
  end
end