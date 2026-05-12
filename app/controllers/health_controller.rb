class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  layout "marketing/base"

  def show
    respond_to do |format|
      format.html { render }
      format.json do
        render json: {
          status: "ok",
          queue: queue_metrics,
          webserver: webserver_metrics
        }
      end
    end
  end

  private def queue_metrics
    Sidekiq::Queue.all.to_h do |queue|
      [queue.name, {
        size: queue.size,
        latency: queue.latency
      }]
    end
  end

  private def webserver_metrics
    response = {
      backlog: 0
    }

    puma_stats = Puma.stats_hash
    if puma_stats.key?(:worker_status)
      response[:clustered] = true
      response[:backlog] = puma_stats[:worker_status].sum { |ws| ws[:last_status][:backlog] }
    else
      response[:backlog] = puma_stats[:backlog]
    end

    response
  end
end
