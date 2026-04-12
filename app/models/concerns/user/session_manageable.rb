module User::SessionManageable
  extend ActiveSupport::Concern

  # Returns an array of hashes representing sessions that currently exist in
  # Redis. Entries in the user index that have expired or whose session key no
  # longer exists (e.g. explicit logout without a clean ZREM) are excluded.
  #
  # Each entry: { sid: String, expires_at: Time, auth_data: Hash | nil }
  # The +sid+ is the private session ID (the Redis key suffix, a SHA-based digest).
  def get_sessions
    XivAuthSessionStore.with_index_redis do |r|
      r.zremrangebyscore(_session_index_key, 0, Time.now.to_i)
      entries = r.zrange(_session_index_key, 0, -1, with_scores: true)
      next [] if entries.empty?

      n = entries.length
      results = r.pipelined do |pipe|
        entries.each { |private_id, _| pipe.get(_canonical_session_key(private_id)) }
        entries.each { |private_id, _| pipe.exists(_canonical_session_key(private_id)) }
      end

      get_results    = results[0...n]
      exists_results = results[n..]

      entries.zip(get_results, exists_results).filter_map do |(private_id, score), raw_data, exists|
        next unless exists > 0

        auth_data = begin
          MessagePack.unpack(raw_data)&.dig("auth_data")&.with_indifferent_access
        rescue StandardError
          nil
        end

        { sid: private_id, expires_at: Time.at(score.to_i), auth_data: auth_data }
      end
    end
  end

  def active_session_count
    get_sessions.length
  end

  # Destroys specific sessions by their private IDs, removing them from both
  # Redis and the user index.
  def destroy_sessions(sid_private_ids)
    return if sid_private_ids.empty?

    XivAuthSessionStore.with_index_redis do |r|
      r.pipelined do |pipe|
        sid_private_ids.each do |sid|
          pipe.del(_canonical_session_key(sid))
          pipe.zrem(_session_index_key, sid)
        end
      end
    end
  end

  private

  def _session_index_key
    "#{XivAuthSessionStore::USER_INDEX_PREFIX}#{id}"
  end

  # Constructs the Redis key where Rack stores the session data for a given
  # private session ID. Mirrors RedisSessionStore's prefixed(sid.private_id).
  def _canonical_session_key(private_id)
    "#{XivAuthSessionStore::SESSION_KEY_PREFIX}#{private_id}"
  end
end
