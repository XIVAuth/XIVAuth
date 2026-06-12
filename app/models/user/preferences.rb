class User::Preferences
  include StoreModel::Model

  enum :theme, %i[auto astral umbral eulmore ishgard gridania thanalan limsa thirteenth]
  enum :pride_flag, PrideHelper::PRIDE_FLAGS + %i[random none]

  def theme
    resolve_enum(:theme, default: "auto")
  end

  def pride_flag
    resolve_enum(:pride_flag, default: "random")
  end

  private def resolve_enum(name, default: nil)
    val = send(:"#{name}_value")
    val.nil? ? default : self.class.send(:"#{name}_values").key(val).to_s
  end
end
