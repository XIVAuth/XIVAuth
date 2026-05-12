class Admin::JwtKeysController < Admin::AdminController
  before_action :set_key, except: %i[index]

  def index
    @jwt_keys = JwtSigningKey.order(created_at: :desc)
  end

  def show; end

  private def set_key
    @key = JwtSigningKey.find_by(name: params[:name])
  end
end
