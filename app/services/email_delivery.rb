module EmailDelivery
  class Error < StandardError; end

  # The provider refused to deliver to this recipient (suppressed after a past bounce/complaint, or hard-bounced
  # during the send).
  class RecipientRejected < Error; end

  # The provider considers the recipient address itself invalid.
  class InvalidRecipient < Error; end

  # Any other delivery failure: timeouts, rate limits, provider outages, rejected requests, etc.
  class Failed < Error; end
end
