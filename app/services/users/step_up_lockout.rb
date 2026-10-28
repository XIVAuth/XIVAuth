class Users::StepUpLockout
  SESSION_KEY = "step_up_lockout".freeze

  MAX_FAILURES = 5
  LOCKOUT_PERIOD = 5.minutes

  def initialize(session)
    @session = session
  end

  def record_failure!
    failures = (stale? ? 0 : data["failures"].to_i) + 1
    @session[SESSION_KEY] = { "failures" => failures, "failed_at" => Time.current.to_i }
  end

  def reset!
    @session.delete(SESSION_KEY)
  end

  def locked_out?
    data["failures"].to_i >= MAX_FAILURES && !stale?
  end

  private def stale?
    Time.zone.at(data["failed_at"].to_i) <= LOCKOUT_PERIOD.ago
  end

  private def data
    @session[SESSION_KEY] || { }
  end
end
