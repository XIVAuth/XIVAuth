class Attachment::GenerateDefaultAvatarJob < ApplicationJob
  RateLimitedError = Class.new(StandardError)

  queue_as :default

  retry_on RateLimitedError
  retry_on Faraday::Error, attempts: 3

  def perform(record_type, record_id, attachment_name)
    record = record_type.safe_constantize&.find_by(id: record_id)
    return if record.nil?
    return if record.public_send(attachment_name).present?

    default_url = record.public_send("default_#{attachment_name}_url")
    response = Faraday.get(default_url) { |req| req.options.open_timeout = 5; req.options.timeout = 10 }

    raise RateLimitedError, "rate limited by #{default_url}" if response.status == 429
    raise Faraday::Error, "unexpected status #{response.status} from #{default_url}" unless response.success?

    record.public_send("#{attachment_name}=", StringIO.new(response.body))
    record.save!
  end
end
