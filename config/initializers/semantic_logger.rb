require "contextual_logger/middleware"
require "contextual_logger/formatters/json_formatter"
require "contextual_logger/formatters/color_formatter"

SemanticLogger.application = "XIVAuth"
SemanticLogger.environment = ENV["APP_ENV"] || Rails.env.to_s

# default log formatter
Rails.application.middleware.insert_before RailsSemanticLogger::Rack::Logger, ContextualLogger::Middleware
