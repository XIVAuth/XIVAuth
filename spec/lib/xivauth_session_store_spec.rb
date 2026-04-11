require "rails_helper"
require "xivauth_session_store"

RSpec.describe XivAuthSessionStore do
  let(:app) { ->(_env) { [200, {}, ["OK"]] } }
  let(:redis_double) { instance_double(Redis) }
  let(:store) do
    allow(Redis).to receive(:new).and_return(redis_double)
    XivAuthSessionStore.new(app, redis: { expire_after: 7.days.to_i })
  end

  let(:sid) { Rack::Session::SessionId.new(SecureRandom.urlsafe_base64(32)) }
  let(:user_id) { SecureRandom.uuid }
  let(:session_data) { { "warden.user.user.key" => [[user_id], nil] }.with_indifferent_access }
  let(:empty_session) { {}.with_indifferent_access }

  def session_key(s = sid)
    "#{XivAuthSessionStore::SESSION_KEY_PREFIX}#{s.private_id}"
  end

  def public_session_key(s = sid)
    "#{XivAuthSessionStore::SESSION_KEY_PREFIX}#{s.public_id}"
  end

  def index_key
    "#{XivAuthSessionStore::USER_INDEX_PREFIX}#{user_id}"
  end

  describe "#write_session" do
    before do
      allow(redis_double).to receive(:setex)
      allow(redis_double).to receive(:set)
      allow(redis_double).to receive(:zadd)
      allow(redis_double).to receive(:expire)
    end

    it "writes session data to Redis with TTL when ttl option is given" do
      expect(redis_double).to receive(:setex).with(session_key, 7.days.to_i, anything)
      store.write_session({}, sid, session_data, { ttl: 7.days.to_i })
    end

    it "writes without expiry when no TTL is configured" do
      store_no_expiry = nil
      allow(Redis).to receive(:new).and_return(redis_double)
      store_no_expiry = XivAuthSessionStore.new(app, redis: {})

      expect(redis_double).to receive(:set).with(session_key, anything)
      store_no_expiry.write_session({}, sid, session_data, {})
    end

    it "indexes the session in the user sorted set when session has Devise user data" do
      expect(redis_double).to receive(:zadd).with(index_key, anything, sid.private_id)
      store.write_session({}, sid, session_data, { ttl: 7.days.to_i })
    end

    it "sets the sorted set expiry slightly longer than the session TTL" do
      expect(redis_double).to receive(:expire).with(index_key, be > 7.days.to_i)
      store.write_session({}, sid, session_data, { ttl: 7.days.to_i })
    end

    it "does not index the session when there is no Devise user data" do
      expect(redis_double).not_to receive(:zadd)
      store.write_session({}, sid, empty_session, { ttl: 7.days.to_i })
    end

    it "returns the sid on success" do
      result = store.write_session({}, sid, session_data, { ttl: 7.days.to_i })
      expect(result).to eq(sid)
    end
  end

  describe "#find_session" do
    context "when the session exists and passes the user index check" do
      before do
        allow(redis_double).to receive(:get).with(session_key).and_return(Marshal.dump(session_data))
        allow(redis_double).to receive(:zscore).with(index_key, sid.private_id).and_return(7.days.from_now.to_f)
      end

      it "returns the original sid and session data" do
        returned_sid, data = store.find_session({}, sid)
        expect(returned_sid).to eq(sid)
        expect(data["warden.user.user.key"]).to be_present
      end
    end

    context "when the session exists but is absent from the user index" do
      before do
        allow(redis_double).to receive(:get).with(session_key).and_return(Marshal.dump(session_data))
        allow(redis_double).to receive(:zscore).with(index_key, sid.private_id).and_return(nil)
        allow(redis_double).to receive(:del)
      end

      it "returns a new empty session" do
        _sid, data = store.find_session({}, sid)
        expect(data).to be_empty
      end

      it "deletes the orphaned Redis key" do
        expect(redis_double).to receive(:del).with(session_key, public_session_key)
        store.find_session({}, sid)
      end
    end

    context "when the session does not exist in Redis" do
      before do
        allow(redis_double).to receive(:get).with(session_key).and_return(nil)
      end

      it "returns a new empty session" do
        _sid, data = store.find_session({}, sid)
        expect(data).to be_empty
      end
    end

    context "when sid is nil" do
      it "returns a new empty session without hitting Redis" do
        expect(redis_double).not_to receive(:get)
        _sid, data = store.find_session({}, nil)
        expect(data).to be_empty
      end
    end

    context "when session has no user data (anonymous session)" do
      before do
        allow(redis_double).to receive(:get).with(session_key).and_return(Marshal.dump(empty_session))
      end

      it "returns the session without performing an index check" do
        expect(redis_double).not_to receive(:zscore)
        returned_sid, data = store.find_session({}, sid)
        expect(returned_sid).to eq(sid)
        expect(data).to be_empty
      end
    end
  end

  describe "#delete_session" do
    before do
      allow(redis_double).to receive(:get).with(session_key).and_return(Marshal.dump(session_data))
      allow(redis_double).to receive(:del)
      allow(redis_double).to receive(:zrem)
    end

    it "deletes the session key from Redis" do
      expect(redis_double).to receive(:del).with(session_key, public_session_key)
      store.delete_session({}, sid, {})
    end

    it "removes the session from the user sorted set index" do
      expect(redis_double).to receive(:zrem).with(index_key, sid.private_id)
      store.delete_session({}, sid, {})
    end

    it "returns a new sid when drop option is false" do
      result = store.delete_session({}, sid, { drop: false })
      expect(result).to be_a(Rack::Session::SessionId)
      expect(result).not_to eq(sid)
    end

    it "returns nil when drop option is true" do
      result = store.delete_session({}, sid, { drop: true })
      expect(result).to be_nil
    end

    context "when the session has no user data" do
      before do
        allow(redis_double).to receive(:get).with(session_key).and_return(Marshal.dump(empty_session))
      end

      it "deletes the key without touching the user index" do
        expect(redis_double).not_to receive(:zrem)
        store.delete_session({}, sid, {})
      end
    end
  end
end
