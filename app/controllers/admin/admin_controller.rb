class Admin::AdminController < ApplicationController
  before_action :authorize_admin!
  before_action :set_default_meta_tags
  layout "portal/page"

  def authorize_admin!
    # n.b. this should already be handled by the routing layer, but we'll put this here for safety's sake as well.
    raise ActionController::RoutingError, "Not Found" unless current_user.admin?
  end

  private def set_default_meta_tags
    set_meta_tags site: "XIVAuth Admin",
                  icon: [
                    { href: helpers.asset_path('logos/xivauth-key-45-red.svg'), type: 'image/svg+xml', sizes: 'any' },
                  ]
  end
end
