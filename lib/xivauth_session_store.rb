require "redis-session-store"

# Slightly more secure session store using 256-bit sessions.
class XivAuthSessionStore < RedisSessionStore
  SESSION_KEY_PREFIX = "xivauth:sessions:v1:sid:"

  private

  def generate_sid
    Rack::Session::SessionId.new(SecureRandom.urlsafe_base64(32))
  end
end
