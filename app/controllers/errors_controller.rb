class ErrorsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  helper ApplicationHelper
  helper ErrorsHelper
  before_action :set_observability_context
  layout "error"

  def show
    @exception = request.env["action_dispatch.exception"]

    @status_code = @exception.try(:status_code) ||
                   ActionDispatch::ExceptionWrapper.new(
                     request.env, @exception
                   ).status_code

    # Return a specific error page for any response, if it exists
    if template_exists? "errors/#{@status_code}"
      render "errors/#{@status_code}", status: @status_code
      return
    end

    # Fallback to a generic error page that matches the requested format, if it exists
    if template_exists? "errors/generic"
      render "errors/generic", status: @status_code, locals: { status: @status_code }
      return
    end

    # Fallback to a specific error page via HTML, if it exists
    if template_exists? "errors/#{@status_code}", formats: [:html]
      render "errors/#{@status_code}", status: @status_code, formats: [:html]
      return
    end

    # Fallback to a generic error page via HTML
    render "errors/generic", status: @status_code, locals: { status: @status_code }, formats: [:html]
  end

  private def set_observability_context
    sentry_frontend_data = {
      environment: ENV["APP_ENV"] || Rails.env,
      dsn: Rails.application.credentials.dig(:sentry, :dsn, :frontend),
      user: { }
    }

    if user_signed_in?
      user_meta = { id: current_user.id, username: current_user.display_name }
      sentry_frontend_data[:user] = user_meta

      Sentry.set_user(user_meta)
    end

    gon.push({ app_env: ENV["APP_ENV"] || Rails.env })
    gon.push({ sentry: sentry_frontend_data })

    trace = {
      "Event ID": (Sentry.last_event_id if defined?(Sentry)),
      "Trace ID": internal_trace_id,
      "Request ID": request.uuid # fallback
    }

    @trace_type, @trace_id = trace.compact_blank.first
  end

  private def internal_trace_id
    return Sentry.get_current_scope&.get_span&.trace_id if defined?(Sentry)

    nil
  end
end
