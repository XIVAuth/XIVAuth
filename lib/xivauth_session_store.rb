require "redis"
require "msgpack"

# Derived from redis-session-store, but with more ✨magic ✨, like user bindings.
#
# Stores sessions in Redis, with a secondary record mapping user IDs to their sessions, so that we can find and
# manage all of a user's sessions.
#
# When sessions are read, we validate that it exists *both* in the session namespace (where data is stored) AND, if
# the session is authenticated, that it also exists in the user's known sessions list. This prevents us from falling out
# of sync if an entry is deleted in one place, but not the other.
class XivAuthSessionStore < ActionDispatch::Session::AbstractSecureStore # rubocop:disable Metrics/ClassLength
  SESSION_KEY_PREFIX = "xivauth:sessions:v1:sid:".freeze
  USER_INDEX_PREFIX  = "xivauth:sessions:v1:usermap:".freeze

  def initialize(app, options = {})
    super
    redis_config  = options.fetch(:redis, {})
    @expire_after = redis_config[:expire_after]
    conn_options  = redis_config.reject { |k, _| %i[expire_after key_prefix].include?(k) }
    @redis        = Redis.new(conn_options)
  end

  # Yields a thread-local Redis connection to the session DB.
  # Used externally by User::SessionManageable for user index operations.
  def self.with_index_redis
    Thread.current[:xivauth_index_redis] ||= Redis.new(session_redis_options)
    yield Thread.current[:xivauth_index_redis]
  end

  def self.session_redis_options
    {
      url:        "#{ENV.fetch('REDIS_URL', 'redis://localhost:6379')}/#{ENV.fetch('REDIS_SESSION_DB_INDEX', 2)}",
      password:   ENV.fetch("REDIS_PASSWORD", nil),
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
    }.compact
  end

  def find_session(_env, sid)
    return session_default_values unless sid

    session_data = fetch_session_data(sid)
    return session_default_values unless session_data

    user_id = extract_devise_user_id(session_data)
    if user_id && !session_in_user_index?(user_id, sid.private_id)
      delete_redis_keys(sid)
      return session_default_values
    end

    [sid, session_data]
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    session_default_values
  end

  def write_session(_env, sid, session_data, options = nil)
    expiry = expiry_for(options)

    if expiry
      @redis.setex(prefixed(sid.private_id), expiry, encode(session_data))
    else
      @redis.set(prefixed(sid.private_id), encode(session_data))
    end

    user_id = extract_devise_user_id(session_data)
    index_session!(user_id, sid.private_id, expiry) if user_id

    sid
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    false
  end

  def delete_session(_env, sid, options)
    session_data = fetch_session_data(sid)
    user_id = extract_devise_user_id(session_data) if session_data

    delete_redis_keys(sid)
    unindex_session!(user_id, sid.private_id) if user_id

    (options || {})[:drop] ? nil : generate_sid
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    generate_sid
  end

  private

  # Prevents a new session from being persisted for read-only requests where
  # the session cookie is present but the session has already expired in Redis.
  def session_exists?(env)
    sid = current_session_id(env)
    return false unless sid.present?

    @redis.exists?(prefixed(sid.private_id))
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    true
  end

  def fetch_session_data(sid)
    raw = @redis.get(prefixed(sid.private_id))
    return nil unless raw

    decode(raw).with_indifferent_access
  rescue StandardError
    nil
  end

  def delete_redis_keys(sid)
    @redis.del(prefixed(sid.private_id), prefixed(sid.public_id))
  end

  def prefixed(sid_str)
    "#{SESSION_KEY_PREFIX}#{sid_str}"
  end

  def encode(session_data)
    MessagePack.pack(session_data)
  end

  def decode(raw)
    MessagePack.unpack(raw)
  rescue StandardError
    # Backward compatibility for sessions serialized before MessagePack rollout.
    # rubocop:disable Security/MarshalLoad
    Marshal.load(raw)
    # rubocop:enable Security/MarshalLoad
  end

  def session_default_values
    [generate_sid, { }.with_indifferent_access]
  end

  def expiry_for(options)
    (options&.[](:ttl) || options&.[](:expire_after) || @expire_after)&.to_i
  end

  def extract_devise_user_id(session)
    session&.dig("warden.user.user.key")&.first&.first
  end

  def session_in_user_index?(user_id, sid_private_id)
    @redis.zscore("#{USER_INDEX_PREFIX}#{user_id}", sid_private_id).present?
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    true
  end

  def index_session!(user_id, sid_private_id, expiry)
    expiry     ||= 7.days.to_i
    expiry_score = Time.now.to_i + expiry
    index_key    = "#{USER_INDEX_PREFIX}#{user_id}"

    @redis.zadd(index_key, expiry_score, sid_private_id)
    @redis.expire(index_key, expiry + 1.day.to_i)
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    nil
  end

  def unindex_session!(user_id, sid_private_id)
    @redis.zrem("#{USER_INDEX_PREFIX}#{user_id}", sid_private_id)
  rescue Errno::ECONNREFUSED, Redis::CannotConnectError
    nil
  end

  # Custom XIVAuth sessionID that doesn't include version fields - we do this at a higher point
  # in the schema.
  class SessionId < Rack::Session::SessionId
    attr_reader :private_id, :public_id

    def private_id
      hash_sid(public_id)
    end
  end

  def generate_sid
    Rack::Session::SessionId.new(SecureRandom.urlsafe_base64(32))
  end
end
