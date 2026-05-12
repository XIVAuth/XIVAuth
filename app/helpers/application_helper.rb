module ApplicationHelper
  def build_auth_data(prefix)
    {
      "#{prefix}_ip": request.ip,
      "#{prefix}_at": Time.current.iso8601,
      "#{prefix}_location": {
        country: request.headers["CF-IPCountry"]&.force_encoding("UTF-8")&.scrub,
        region: request.headers["CF-Region"]&.force_encoding("UTF-8")&.scrub,
        city: request.headers["CF-IPCity"]&.force_encoding("UTF-8")&.scrub
      }.compact.presence
    }
  end

  def parse_user_agent(user_agent)
    b = Browser.new(user_agent)
    type = if b.device.tablet?
             "tablet"
           elsif b.device.mobile?
             "mobile"
           else
             case b.name
             when "Firefox" then "firefox"
             when "Chrome"  then "chrome"
             when "Safari"  then "safari"
             when "Edge"    then "edge"
             when "Opera"   then "opera"
             when "Brave"   then "brave"
             else                "unknown"
             end
           end
    {
      name: b.name,
      version: b.full_version,
      os: b.platform.name,
      os_version: b.platform.version,
      device: b.device.name,
      type: type,
      user_agent: user_agent
    }.compact
  end

  delegate :commit_hash, to: :EnvironmentInfo

  delegate :hosting_provider, to: :EnvironmentInfo

  delegate :environment, to: :EnvironmentInfo

  def lower_environment?
    !Rails.env.production? || (ENV["APP_ENV"] != "production")
  end
end
