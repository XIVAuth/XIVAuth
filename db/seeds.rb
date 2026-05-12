Rails.root.glob("db/seeds/*.rb").each do |seed|
  load seed
end

Rails.root.glob("db/seeds/#{Rails.env}/*.rb").each do |seed|
  load seed
end
