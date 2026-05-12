require "contextual_logger"
require "contextual_logger/log_context"

class ContextualLogger::Middleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    LogContext.clear

    [status, headers, response]
  end
end
