require "rails_helper"

RSpec.describe Users::StepUpLockout do
  include ActiveSupport::Testing::TimeHelpers

  let(:session) { { } }
  let(:lockout) { described_class.new(session) }

  it "locks out after the maximum number of failures" do
    (described_class::MAX_FAILURES - 1).times { lockout.record_failure! }
    expect(lockout.locked_out?).to be(false)

    lockout.record_failure!
    expect(lockout.locked_out?).to be(true)
  end

  it "unlocks after the lockout period and starts counting again" do
    described_class::MAX_FAILURES.times { lockout.record_failure! }

    travel(described_class::LOCKOUT_PERIOD + 1.second) do
      expect(lockout.locked_out?).to be(false)

      lockout.record_failure!
      expect(lockout.locked_out?).to be(false)
    end
  end

  it "clears on reset" do
    described_class::MAX_FAILURES.times { lockout.record_failure! }
    lockout.reset!

    expect(lockout.locked_out?).to be(false)
  end
end
