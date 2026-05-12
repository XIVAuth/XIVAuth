module EnvironmentInfo
  def self.commit_hash
    ENV["COMMIT_HASH"] || ENV["RAILWAY_GIT_COMMIT_SHA"] || ENV["HEROKU_SLUG_COMMIT"] || nil
  end

  def self.hosting_provider
    if ENV["HEROKU_APP_NAME"]
      :heroku
    elsif ENV["RAILWAY_SERVICE_ID"]
      :railway
    elsif ENV["container"] == "podman"
      :podman
    end
  end

  def self.environment
    ENV["APP_ENV"] || Rails.env
  end
end
