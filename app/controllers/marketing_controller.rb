class MarketingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "marketing/base"

  def index
    @counts = {
      users: User.count,
      characters: CharacterRegistration.verified.count,
      applications: ClientApplication.count,
      verification_rate: (CharacterRegistration.verified.count.to_f / FFXIV::Character.count * 100).round(1)
    }

    render :index
  end

  def flarestone; end

  def discord
    redirect_to "https://discord.com/invite/nFPPTcDDgH", allow_other_host: true
  end
end
