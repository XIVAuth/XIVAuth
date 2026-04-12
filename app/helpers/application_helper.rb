module ApplicationHelper
  def build_auth_data(prefix)
    {
      "#{prefix}_ip":       request.ip,
      "#{prefix}_at":       Time.now.utc.iso8601,
      "#{prefix}_location": {
        country: request.headers["CF-IPCountry"],
        region:  request.headers["CF-IPRegion"],
        city:    request.headers["CF-IPCity"]
      }.compact.presence
    }
  end

  def parse_user_agent(ua)
    b = Browser.new(ua)
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
      else                "unknown"
      end
    end
    {
      name:       b.name,
      version:    b.full_version,
      os:         b.platform.name,
      os_version: b.platform.version,
      device:     b.device.name,
      type:       type,
      user_agent: ua
    }.compact
  end

  def commit_hash
    EnvironmentInfo.commit_hash
  end

  def hosting_provider
    EnvironmentInfo.hosting_provider
  end

  def environment
    EnvironmentInfo.environment
  end

  def lower_environment?
    !Rails.env.production? || (ENV["APP_ENV"] != "production")
  end
end
