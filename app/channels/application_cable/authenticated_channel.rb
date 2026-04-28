module ApplicationCable
  class AuthenticatedChannel < ActionCable::Channel::Base
    delegate :session, :ability, to: :connection
    protected :session, :ability

    before_subscribe :require_authenticated!

    private def require_authenticated!
      reject unless current_user
    end
  end
end
