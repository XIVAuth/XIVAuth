class MarketingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "marketing/base"

  def index
    @counts = {
      users: User.count,
      characters: CharacterRegistration.verified.count,
      applications: ClientApplication.count,
      headpats: Rails.cache.read("marketing:headpats", raw: true).to_i,
    }

    render :index
  end

  rate_limit to: 1, within: 1.minute, by: -> { request.remote_ip },
             with: -> { render_pet_cooldown },
             only: :headpat

  rate_limit to: 1, within: 1.minute, by: -> { session.id.to_s },
             with: -> { render_pet_cooldown },
             only: :headpat

  def headpat
    count = Rails.cache.increment("marketing:headpats")

    Turbo::StreamsChannel.broadcast_replace_to(
      "marketing",
      target: "headpats_card",
      partial: "marketing/headpats_card",
      locals: { count: count }
    )

    render turbo_stream: turbo_stream.append(
      "toasts",
      partial: "layouts/components/toasts/toast",
      locals: {
        title: "Headpat delivered!",
        message: "You've given our Miqo a headpat! She says thank you~",
        color: "success",
        notification_icon_class: "fa-solid fa-cat text-success",
        toast_id: "marketing_headpat_d3592386-79df-478e-8e2b-8f8bc35a8b66",
        timestamp: Time.current.to_i,
      }
    )

    Sentry.metrics.count(
      "xivauth.headpat",
      value: 1,
      attributes: {
        "user.authenticated": current_user.present?,
        "user.id": current_user&.id,
        "network.ip": request.remote_ip
      }
    )
  end

  def flarestone; end

  def discord
    redirect_to "https://discord.com/invite/nFPPTcDDgH", allow_other_host: true
  end

  private def render_pet_cooldown
    render turbo_stream: turbo_stream.append(
      "toasts",
      partial: "layouts/components/toasts/toast",
      locals: {
        title: "Too many headpats!",
        message: "Our Miqo is still enjoying your last headpat. Give it a little bit before petting them again!",
        color: "warning",
        notification_icon_class: "fa-solid fa-cat text-warning",
        toast_id: "marketing_headpat_d3592386-79df-478e-8e2b-8f8bc35a8b66",
        timestamp: Time.current.to_i,
      }
    )
  end
end
