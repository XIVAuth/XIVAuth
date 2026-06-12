class User::Preferences
  include StoreModel::Model

  enum :theme, %i[auto astral umbral eulmore ishgard gridania thanalan limsa thirteenth]
  enum :pride_flag, PrideHelper::PRIDE_FLAGS + %i[random none]
  
  def theme
    self[:theme].nil? ? :auto : super
  end
  
  def pride_flag
    self[:pride_flag].nil? ? :random : super
  end
end
