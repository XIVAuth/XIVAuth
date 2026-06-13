# frozen_string_literal: true

class DynamicAssets::WebauthnAuthenticatorsController < ApplicationController
  skip_before_action :authenticate_user!

  before_action :load_device_class

  def icon_dark
    serve_icon(@device_class.icon_dark)
  end

  def icon_light
    serve_icon(@device_class.icon_light)
  end

  private

  def load_device_class
    @device_class = Webauthn::DeviceClass.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def serve_icon(data_uri)
    match = data_uri.match(/\Adata:([^;]+);base64,(.+)\z/m)
    return head :unprocessable_entity unless match

    mime_type = match[1]
    data = Base64.decode64(match[2])

    expires_in 2.weeks, public: true
    response.headers["Last-Modified"] = @device_class.updated_at.httpdate

    send_data data, type: mime_type, disposition: "inline"
  end
end
