class MarketingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "marketing/base"

  def index
    @counts = {
      users: User.count,
      characters: CharacterRegistration.verified.count,
      applications: ClientApplication.count,
      verification_rate: (CharacterRegistration.verified.count.to_f / FFXIV::Character.count * 100).round(1),
      headpats: Rails.cache.read("marketing:headpats").to_i,
    }

    render :index
  end

  def headpat
    count = Rails.cache.increment("marketing:headpats")

    Turbo::StreamsChannel.broadcast_replace_to(
      "marketing",
      target: "headpats_card",
      partial: "marketing/headpats_card",
      locals: { count: count }
    )

    head :created
  end

  def flarestone; end

  def discord
    redirect_to "https://discord.com/invite/nFPPTcDDgH", allow_other_host: true
  end
end
