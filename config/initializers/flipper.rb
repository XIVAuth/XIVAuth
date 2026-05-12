Flipper.register(:admins) do |actor, _ctx|
  actor.respond_to?(:admin?) && actor.admin?
end

Flipper.register(:developers) do |actor, _ctx|
  actor.respond_to?(:developer?) && actor.developer?
end

Flipper::UI.configure do |config|
  config.application_breadcrumb_href = "/"
  config.cloud_recommendation = false
  config.show_feature_description_in_list = true
end
