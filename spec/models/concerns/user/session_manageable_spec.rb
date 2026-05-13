require "rails_helper"

RSpec.describe User::SessionManageable do
  let(:user) { FactoryBot.create(:user) }
  let(:sid_near) { SecureRandom.urlsafe_base64(32) }
  let(:sid_far) { SecureRandom.urlsafe_base64(32) }
  let(:expiry_date_near) { 3.days.from_now }
  let(:expiry_date_far) { 7.days.from_now }
  let(:redis_double) { instance_double(Redis) }

  before do
    allow(XivAuthSessionStore).to receive(:with_index_redis).and_yield(redis_double)
  end

  def index_key
    "#{XivAuthSessionStore::USER_INDEX_PREFIX}#{user.id}"
  end

  def session_key(private_id)
    "#{XivAuthSessionStore::SESSION_KEY_PREFIX}#{private_id}"
  end

  describe "#get_sessions" do
    before do
      allow(redis_double).to receive(:zremrangebyscore)
    end

    context "when all sessions have live Redis keys" do
      before do
        allow(redis_double).to receive(:zrange).and_return([
                                                             [sid_near, expiry_date_near.to_f],
                                                             [sid_far, expiry_date_far.to_f]
                                                           ])
        allow(redis_double).to receive(:get)
        allow(redis_double).to receive(:pipelined).and_yield(redis_double).and_return([nil, 1, nil, 1])
        allow(redis_double).to receive(:exists)
      end

      it "returns both sessions" do
        expect(user.active_sessions.length).to eq(2)
      end

      it "returns hashes with :sid and :expires_at" do
        sessions = user.active_sessions
        expect(sessions.first[:sid]).to eq(sid_near)
        expect(sessions.first[:expires_at]).to be_within(1.second).of(expiry_date_near)
        expect(sessions.last[:sid]).to eq(sid_far)
        expect(sessions.last[:expires_at]).to be_within(1.second).of(expiry_date_far)
      end
    end

    context "when a session is in the index but its Redis key no longer exists" do
      before do
        allow(redis_double).to receive(:zrange).and_return([
                                                             [sid_near, expiry_date_near.to_f],
                                                             [sid_far, expiry_date_far.to_f]
                                                           ])
        # private_id_2 no longer exists
        allow(redis_double).to receive(:get)
        allow(redis_double).to receive(:pipelined).and_yield(redis_double).and_return([nil, 1, nil, 0])
        allow(redis_double).to receive(:exists)
      end

      it "excludes the stale session" do
        sessions = user.active_sessions
        expect(sessions.length).to eq(1)
        expect(sessions.first[:sid]).to eq(sid_near)
      end
    end

    context "when the user has no sessions in the index" do
      before do
        allow(redis_double).to receive(:zrange).and_return([])
      end

      it "returns an empty array" do
        expect(user.active_sessions).to eq([])
      end
    end

    it "prunes expired entries from the sorted set before reading" do
      allow(redis_double).to receive(:zrange).and_return([])
      expect(redis_double).to receive(:zremrangebyscore).with(
        index_key, 0, be_within(2).of(Time.now.to_i)
      )
      user.active_sessions
    end
  end

  describe "#active_session_count" do
    it "returns the number of sessions that truly exist in Redis" do
      allow(redis_double).to receive(:zremrangebyscore)
      allow(redis_double).to receive(:zrange).and_return([
                                                           [sid_near, expiry_date_near.to_f],
                                                           [sid_far, expiry_date_far.to_f]
                                                         ])
      allow(redis_double).to receive(:get)
      allow(redis_double).to receive(:pipelined).and_yield(redis_double).and_return([nil, 1, nil, 0])
      allow(redis_double).to receive(:exists)

      expect(user.active_session_count).to eq(1)
    end
  end

  describe "#destroy_sessions" do
    let(:pipeline_double) { instance_double(Redis) }

    before do
      allow(redis_double).to receive(:pipelined).and_yield(pipeline_double)
      allow(pipeline_double).to receive(:del)
      allow(pipeline_double).to receive(:zrem)
    end

    it "deletes each session's canonical Redis key" do
      expect(pipeline_double).to receive(:del).with(session_key(sid_near))
      expect(pipeline_double).to receive(:del).with(session_key(sid_far))
      user.destroy_sessions([sid_near, sid_far])
    end

    it "removes each session from the user index" do
      expect(pipeline_double).to receive(:zrem).with(index_key, sid_near)
      expect(pipeline_double).to receive(:zrem).with(index_key, sid_far)
      user.destroy_sessions([sid_near, sid_far])
    end

    it "is a no-op when given an empty array" do
      expect(redis_double).not_to receive(:pipelined)
      user.destroy_sessions([])
    end
  end
end
