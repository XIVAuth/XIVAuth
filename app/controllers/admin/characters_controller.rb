class Admin::CharactersController < Admin::AdminController
  include Pagy::Method

  layout "portal/base"

  before_action :set_character, except: %i[index]

  def index
    @pagy, @characters = pagy(FFXIV::Character.includes(:ban, :character_registrations).order(created_at: :desc))
  end

  def show
    @verified_registration = @character.character_registrations.verified.first
  end

  def destroy
    if @character.destroy
      redirect_to admin_characters_path, notice: "Character deleted."
    else
      redirect_to admin_character_path(@character), alert: "Character could not be deleted."
    end
  end

  def refresh
    if FFXIV::RefreshCharactersJob.perform_later(@character, force_refresh: true)
      respond_to do |format|
        format.html do
          flash[:notice] = "Character refresh was successfully enqueued."
          redirect_back_or_to(admin_character_path(@character.lodestone_id))
        end
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Character refresh could not be enqueued."
          redirect_back_or_to(admin_character_path(@character.lodestone_id))
        end
      end
    end
  end

  def force_register; end

  private def set_character
    @character = FFXIV::Character.find_by(lodestone_id: params[:lodestone_id])
  end
end
