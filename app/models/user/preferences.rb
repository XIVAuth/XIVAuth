class User::Preferences
  include StoreModel::Model

  enum :theme, %i[auto astral umbral eulmore ishgard gridania thanalan limsa thirteenth], default: :auto
  enum :pride_flag, PrideHelper::PRIDE_FLAGS + %i[random none], default: :random
end
