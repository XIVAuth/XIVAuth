class ApplicationCable::Connection < ActionCable::Connection::Base
  identified_by :current_user

  def connect
    self.current_user = find_user
  end

  def ability
    @ability ||= Abilities::UserAbility.new(current_user) if current_user
  end

  protected def find_user
    env["warden"].user # nil for unauthenticated guests; channels enforce their own auth
  end
end
