require "rails_helper"

RSpec.describe Users::AuthnContext do
  include ActiveSupport::Testing::TimeHelpers

  let(:session) { { } }
  let(:context) { described_class.new(session) }

  describe "#record_login!" do
    it "records a login without MFA" do
      context.record_login!(%w[pwd])

      expect(context.amr).to eq(%w[pwd])
      expect(context.auth_time).to be_present
      expect(context.mfa_time).to be_nil
    end

    it "records a login with MFA" do
      context.record_login!(%w[pwd otp], mfa: true)

      expect(context.amr).to eq(%w[pwd otp mfa])
      expect(context.mfa_time).to eq(context.auth_time)
    end

    it "replaces any previous context" do
      context.record_login!(%w[pwd otp], mfa: true)
      context.record_login!(%w[fed])

      expect(context.amr).to eq(%w[fed])
      expect(context.mfa_time).to be_nil
    end
  end

  describe "#record_step_up!" do
    it "adds the method and moves mfa_time forward without changing auth_time" do
      context.record_login!(%w[pwd])
      auth_time = context.auth_time

      travel 10.minutes do
        context.record_step_up!(:webauthn)

        expect(context.amr).to eq(%w[pwd hwk mfa])
        expect(context.auth_time).to eq(auth_time)
        expect(context.mfa_time).to eq(Time.zone.at(Time.current.to_i))
      end
    end
  end

  describe "#mfa_fresh?" do
    it "is false without an MFA proof" do
      context.record_login!(%w[pwd])

      expect(context.mfa_fresh?(within: 1.hour)).to be(false)
    end

    it "honours the window" do
      context.record_step_up!(:totp)

      expect(context.mfa_fresh?(within: 5.minutes)).to be(true)
      travel(6.minutes) { expect(context.mfa_fresh?(within: 5.minutes)).to be(false) }
    end

    it "never matches a zero window" do
      context.record_step_up!(:totp)

      expect(context.mfa_fresh?(within: 0)).to be(false)
    end
  end
end
