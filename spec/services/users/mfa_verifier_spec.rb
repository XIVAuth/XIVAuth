require "rails_helper"

RSpec.describe Users::MFAVerifier do
  let(:user) { FactoryBot.create(:user) }

  describe "#verify!" do
    it "raises when no proof is supplied" do
      expect { described_class.new(user).verify! }
        .to raise_error(described_class::VerificationError, "invalid context")
    end

    context "with TOTP" do
      let(:totp_secret) { ROTP::Base32.random }

      it "raises when TOTP is not configured" do
        expect { described_class.new(user, otp_attempt: "123456").verify! }
          .to raise_error(described_class::VerificationError) { |e| expect(e.method).to eq("TOTP") }
      end

      context "when TOTP is enabled" do
        before do
          FactoryBot.create(:users_totp_credential, user: user, otp_secret: totp_secret, otp_enabled: true)
        end

        it "returns :totp for a valid code" do
          code = ROTP::TOTP.new(totp_secret).now
          expect(described_class.new(user, otp_attempt: code).verify!).to eq(:totp)
        end

        it "raises for an invalid code" do
          expect { described_class.new(user, otp_attempt: "000000").verify! }
            .to raise_error(described_class::VerificationError, /invalid/)
        end
      end
    end

    context "with WebAuthn" do
      it "raises when no challenge was issued" do
        expect { described_class.new(user, webauthn_response: "{}").verify! }
          .to raise_error(described_class::VerificationError) { |e| expect(e.method).to eq("WebAuthn") }
      end
    end
  end
end
