class User::Preferences
  include StoreModel::Model

  enum :theme, %i[auto astral umbral eulmore ishgard gridania thanalan limsa thirteenth]
  enum :pride_flag, PrideHelper::PRIDE_FLAGS + %i[random none]
  
  def theme
    super || :auto
  end
  
  def pride_flag
    super || :random
  end
end
