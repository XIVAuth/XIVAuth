class MarketingChannel < ApplicationCable::PublicChannel
  def subscribed
    stream_from "marketing"
  end
end
