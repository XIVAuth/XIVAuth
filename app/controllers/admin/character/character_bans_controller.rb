class Admin::Character::CharacterBansController < Admin::AdminController
  before_action :load_context

  def show
    render json: @character.ban
  end

  def new
    @ban = @character.build_ban
  end

  def create
    @character.character_registrations.destroy_all if params.dig(:character_ban, :remove_registrations) == "1"
    @ban = @character.build_ban(filtered_params)

    if @ban.save
      respond_to do |format|
        format.html { redirect_to admin_character_path(@character.lodestone_id), notice: "Character banned." }
      end
    else
      render_new_form_again
    end
  end

  def destroy
    if @character.ban&.destroy
      respond_to do |format|
        format.html { redirect_to admin_character_path(@character.lodestone_id), notice: "Character unbanned." }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to admin_character_path(@character.lodestone_id), notice: "Character could not be unbanned."
        end
      end
    end
  end

  private def load_context
    @character = FFXIV::Character.find_by(lodestone_id: params[:character_lodestone_id])
  end

  private def filtered_params
    params.expect(character_ban: [:reason])
  end

  private def render_new_form_again(status: :unprocessable_content)
    render status: status,
           turbo_stream: turbo_stream.update("ban_character_modal-content",
                                             partial: "admin/character/character_bans/form")
  end
end
