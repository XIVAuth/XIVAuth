require "rails_helper"

RSpec.describe AttestationJwt, type: :model do
  # Create a default key for tests that rely on automatic key selection
  # Default subject uses HMAC for performance
  subject(:jwt) { described_class.new(algorithm: "HS256", signing_key: hmac_key) }

  let!(:default_key) { FactoryBot.create(:jwt_signing_keys_ed25519) }

  # Use HMAC for performance in most tests
  let(:hmac_key) { FactoryBot.create(:jwt_signing_keys_hmac) }
  let(:disabled_key) { FactoryBot.create(:jwt_signing_keys_hmac, enabled: false) }
  let(:expired_key) { FactoryBot.create(:jwt_signing_keys_hmac, expires_at: 1.hour.ago) }

  describe "initialization and defaults" do
    subject(:jwt) { described_class.new }

    it "creates a new JWT with default parameters" do
      expect(jwt).to be_valid
      expect(jwt.algorithm).to eq(JwtSigningKey::DEFAULT_ALGORITHM)
      expect(jwt.signing_key).to be_present
      expect(jwt.issuer).to eq(ENV.fetch("APP_URL", "https://xivauth.net"))
      expect(jwt.jwt_id).to be_present
      expect(jwt.header["jku"]).to eq("#{ENV.fetch('APP_URL', 'https://xivauth.net')}/api/v1/jwt/jwks")
    end

    it "allows custom algorithm to be set" do
      hmac_key # Ensure HMAC key exists

      jwt = described_class.new(algorithm: "HS256")

      expect(jwt.algorithm).to eq("HS256")
      expect(jwt.signing_key).to be_a(JwtSigningKeys::HMAC)
    end

    it "allows custom body and header attributes" do
      jwt = described_class.new(
        body_attrs: { "custom_claim" => "value" },
        header_attrs: { "custom_header" => "header_value" }
      )

      expect(jwt.body["custom_claim"]).to eq("value")
      expect(jwt.header["custom_header"]).to eq("header_value")
    end

    it "allows setting fields via helper fields" do
      jwt = described_class.new(
        issuer: "https://example.com",
        subject: "user123",
        claim_type: "test"
      )

      expect(jwt.issuer).to eq("https://example.com")
      expect(jwt.subject).to eq("user123")
      expect(jwt.claim_type).to eq("test")
    end
  end

  describe "signed? and frozen behavior" do
    it "reports signed? as false for new JWTs" do
      expect(jwt.signed?).to be false
    end

    it "reports signed? as true after calling token" do
      jwt.token

      expect(jwt.signed?).to be true
    end

    it "prevents mutations after signing" do
      jwt.token

      # Setters are prevented
      expect { jwt.subject = "new_subject" }.to raise_error(AttestationJwt::SignedTokenError)
      expect { jwt.signing_key = hmac_key }.to raise_error(AttestationJwt::SignedTokenError)
    end
  end

  describe "field accessors" do
    describe "issued_at" do
      it "sets and retrieves issued_at as Time" do
        time = 1.hour.ago
        jwt.issued_at = time

        expect(jwt.issued_at).to be_within(1.second).of(time)
      end

      it "accepts Unix timestamp" do
        timestamp = Time.now.to_i - 3600
        jwt.issued_at = timestamp

        expect(jwt.issued_at.to_i).to eq(timestamp)
      end

      it "writes to JWT body during managed field population" do
        time = 1.hour.ago
        jwt.issued_at = time
        jwt.send(:set_managed_fields)

        expect(jwt.body["iat"]).to eq(time.to_i)
      end

      it "raises error for invalid types" do
        expect { jwt.issued_at = "invalid" }.to raise_error(ArgumentError)
      end
    end

    describe "expires_at" do
      it "sets and retrieves expires_at as Time" do
        time = 1.hour.from_now
        jwt.expires_at = time

        expect(jwt.expires_at).to be_within(1.second).of(time)
      end

      it "accepts Unix timestamp" do
        timestamp = Time.now.to_i + 3600
        jwt.expires_at = timestamp

        expect(jwt.expires_at.to_i).to eq(timestamp)
      end

      it "writes to JWT body during managed field population" do
        time = 1.hour.from_now
        jwt.expires_at = time
        jwt.send(:set_managed_fields)

        expect(jwt.body["exp"]).to eq(time.to_i)
      end

      it "accepts ActiveSupport::Duration via expires_in" do
        jwt.expires_in = 1.hour

        # expires_at returns a preview calculated from current time
        expect(jwt.expires_at).to be_within(5.seconds).of(1.hour.from_now)
      end

      it "resolves duration at managed field population" do
        jwt.issued_at = Time.current
        jwt.expires_in = 1.hour

        jwt.send(:set_managed_fields)

        expect(jwt.body["exp"]).to be_within(5).of(Time.now.to_i + 3600)
      end

      it "clamps to signing key expiration" do
        short_lived_key = FactoryBot.create(:jwt_signing_keys_hmac, expires_at: 10.minutes.from_now)
        jwt = described_class.new(algorithm: "HS256", signing_key: short_lived_key)
        jwt.expires_at = 1.hour.from_now

        # Should be clamped to key expiration
        expect(jwt.expires_at.to_i).to be_within(1).of(short_lived_key.expires_at.to_i)
      end

      it "raises error for invalid types" do
        expect { jwt.expires_at = "invalid" }.to raise_error(ArgumentError)
      end
    end

    describe "not_before" do
      it "sets and retrieves not_before as Time" do
        time = 1.hour.ago
        jwt.not_before = time

        expect(jwt.not_before).to be_within(1.second).of(time)
      end

      it "accepts Unix timestamp" do
        timestamp = Time.now.to_i - 3600
        jwt.not_before = timestamp

        expect(jwt.not_before.to_i).to eq(timestamp)
      end

      it "writes to JWT body" do
        time = 1.hour.from_now
        jwt.not_before = time

        expect(jwt.body["nbf"]).to eq(time.to_i)
      end

      it "raises error for invalid types" do
        expect { jwt.not_before = "invalid" }.to raise_error(ArgumentError)
      end
    end

    describe "subject" do
      it "sets and retrieves subject" do
        jwt.subject = "user123"

        expect(jwt.subject).to eq("user123")
        expect(jwt.body["sub"]).to eq("user123")
      end
    end

    describe "audience" do
      it "sets and retrieves audience as string" do
        jwt.audience = "https://example.com"

        expect(jwt.audience).to eq("https://example.com")
        expect(jwt.body["aud"]).to eq("https://example.com")
      end

      it "auto-formats ClientApplication to URL during managed field population" do
        app = FactoryBot.create(:client_application)
        jwt.audience = app

        jwt.send(:set_managed_fields)

        expect(jwt.body["aud"]).to eq("https://xivauth.net/applications/#{app.id}")
      end

      it "retrieves ClientApplication object before signing" do
        app = FactoryBot.create(:client_application)
        jwt.audience = app

        expect(jwt.audience).to eq(app)
      end

      it "returns raw string for non-ClientApplication URLs" do
        jwt.audience = "https://example.com"

        expect(jwt.audience).to eq("https://example.com")
      end

      it "raises error for invalid types" do
        expect { jwt.audience = 123 }.to raise_error(ArgumentError)
      end
    end

    describe "authorized_party" do
      it "sets and retrieves authorized_party as ClientApplication" do
        app = FactoryBot.create(:client_application)
        aud_app = FactoryBot.create(:client_application)
        aud_app.obo_authorizations << app

        jwt.authorized_party = app
        jwt.audience = aud_app

        expect(jwt.authorized_party).to eq(app)
      end

      it "writes to JWT body during managed field population" do
        app = FactoryBot.create(:client_application)
        aud_app = FactoryBot.create(:client_application)
        aud_app.obo_authorizations << app

        jwt.authorized_party = app
        jwt.audience = aud_app
        jwt.send(:set_managed_fields)

        expect(jwt.body["azp"]).to eq("https://xivauth.net/applications/#{app.id}")
      end

      it "returns raw string from body if not set via setter" do
        jwt.body["azp"] = "https://example.com/custom"

        expect(jwt.authorized_party).to eq("https://example.com/custom")
      end

      it "raises error for invalid types" do
        expect { jwt.authorized_party = "string" }.to raise_error(ArgumentError)
      end
    end

    describe "signing_key" do
      it "sets and retrieves signing key" do
        jwt.signing_key = hmac_key

        expect(jwt.signing_key).to eq(hmac_key)
      end

      it "sets kid header during managed field population" do
        expect(jwt.header["kid"]).to be_nil

        jwt.send(:set_managed_fields)

        expect(jwt.header["kid"]).to eq(hmac_key.name)
      end

      it "rejects non-JwtSigningKey types" do
        expect { jwt.signing_key = "invalid" }.to raise_error(ArgumentError, /must be a JwtSigningKey/)
      end
    end
  end

  describe "validation - signing key" do
    it "validates signing key is active when generating" do
      jwt = described_class.new(algorithm: "HS256", signing_key: disabled_key)

      expect(jwt).not_to be_valid
      expect(jwt.errors[:signing_key]).to include("was disabled")
    end

    it "validates signing key is not expired when generating" do
      jwt = described_class.new(algorithm: "HS256", signing_key: expired_key)

      expect(jwt).not_to be_valid
      expect(jwt.errors[:signing_key]).to include("has expired")
    end

    it "validates algorithm is compatible with signing key" do
      rsa_key = FactoryBot.create(:jwt_signing_keys_rsa)
      jwt = described_class.new(algorithm: "HS256", signing_key: rsa_key)

      expect(jwt).not_to be_valid
      expect(jwt.errors[:algorithm]).to be_present
    end
  end

  describe "validation - temporal claims" do
    it "validates issued_at is not in the future" do
      jwt.issued_at = 1.hour.from_now

      expect(jwt).not_to be_valid
      expect(jwt.errors[:issued_at]).to include("is in the future")
    end

    it "validates expires_at is not in the past" do
      jwt.expires_at = 1.hour.ago

      expect(jwt).not_to be_valid
      expect(jwt.errors[:expires_at]).to include("is in the past")
    end

    it "validates exp is after iat in JWT body" do
      jwt.issued_at = 1.hour.from_now
      jwt.expires_at = 30.minutes.from_now

      jwt.send(:set_managed_fields)

      expect(jwt).not_to be_valid
      expect(jwt.errors[:expires_at]).to include("must be after issued_at")
    end

    it "validates exp is after nbf in JWT body" do
      jwt.not_before = 1.hour.ago
      jwt.expires_at = 2.hours.ago

      expect(jwt).not_to be_valid
      expect(jwt.errors[:expires_at]).to include("must be after not_before")
    end

    it "allows valid temporal claims" do
      jwt.issued_at = 1.hour.ago
      jwt.expires_at = 1.hour.from_now
      jwt.not_before = 1.hour.ago

      expect(jwt).to be_valid
    end
  end

  describe "validation - issuer" do
    it "validates issuer is present" do
      jwt.issuer = nil

      expect(jwt).not_to be_valid
      expect(jwt.errors[:issuer]).to include("is not set")
    end

    it "validates issuer matches expected URL" do
      jwt.issuer = "https://evil.com"

      expect(jwt).not_to be_valid
      expect(jwt.errors[:issuer]).to include("is not valid")
    end

    it "allows issuer with expected URL prefix" do
      expected_url = ENV.fetch("APP_URL", "https://xivauth.net")
      jwt.issuer = "#{expected_url}/sandbox"

      expect(jwt).to be_valid
    end
  end

  describe "validation - audience and authorized party" do
    it "validates azp is authorized for audience" do
      azp_app = FactoryBot.create(:client_application)
      aud_app = FactoryBot.create(:client_application)

      jwt.authorized_party = azp_app
      jwt.audience = aud_app

      expect(jwt).not_to be_valid
      expect(jwt.errors[:authorized_party].join).to include("is not authorized")
    end

    it "allows azp when properly authorized" do
      azp_app = FactoryBot.create(:client_application)
      aud_app = FactoryBot.create(:client_application)
      aud_app.obo_authorizations << azp_app

      jwt.authorized_party = azp_app
      jwt.audience = aud_app

      expect(jwt).to be_valid
    end

    it "writes correct URLs to body during managed field population" do
      azp_app = FactoryBot.create(:client_application)
      aud_app = FactoryBot.create(:client_application)
      aud_app.obo_authorizations << azp_app

      jwt.authorized_party = azp_app
      jwt.audience = aud_app
      jwt.send(:set_managed_fields)

      expect(jwt.body["aud"]).to eq("https://xivauth.net/applications/#{aud_app.id}")
      expect(jwt.body["azp"]).to eq("https://xivauth.net/applications/#{azp_app.id}")
    end
  end

  describe "token generation" do
    it "generates a valid token" do
      jwt.subject = "test_subject"

      token = jwt.token

      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3)
    end

    it "produces JWT with same content as post-managed-fields state" do
      jwt.subject = "test_user"
      jwt.expires_in = 1.hour
      jwt.body["custom"] = "value"
      jwt.header["custom_header"] = "header_value"

      # Capture state after managed field population
      jwt.send(:set_managed_fields)
      expected_body = jwt.body.dup
      expected_header = jwt.header.dup

      # Sign and decode
      token = jwt.token
      decoded = JWT.decode(token, nil, false)
      actual_body = decoded[0]
      actual_header = decoded[1]

      # Verify they match exactly - no divergence between preload and signed state
      expect(actual_body).to eq(expected_body)
      expect(actual_header).to eq(expected_header)
    end

    it "auto-populates issued_at if not set" do
      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(Time.zone.at(decoded[0]["iat"])).to be_within(5.seconds).of(Time.current)
    end

    it "preserves custom issued_at" do
      custom_time = 1.hour.ago
      jwt.issued_at = custom_time

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[0]["iat"]).to be_within(1).of(custom_time.to_i)
    end

    it "raises validation error for invalid JWT" do
      jwt = described_class.new(algorithm: "HS256", signing_key: disabled_key)

      expect { jwt.token }.to raise_error(ActiveModel::ValidationError)
    end

    it "includes all custom claims in token" do
      jwt.body["custom_claim"] = "custom_value"
      jwt.body["nested"] = { "key" => "value" }

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[0]["custom_claim"]).to eq("custom_value")
      expect(decoded[0]["nested"]["key"]).to eq("value")
    end

    it "includes all custom headers in token" do
      jwt.header["custom_header"] = "header_value"

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[1]["custom_header"]).to eq("header_value")
    end

    it "includes kid in token header" do
      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[1]["kid"]).to eq(hmac_key.name)
    end
  end

  describe "to_s and inspect" do
    it "returns token string for to_s" do
      token = jwt.token

      expect(jwt.to_s).to eq(token)
    end

    it "returns helpful debug info for inspect" do
      expect(jwt.inspect).to include("signed=")
      expect(jwt.inspect).to include("kid=")
    end
  end

  describe "edge cases and security" do
    subject(:jwt) { described_class.new }

    it "handles missing algorithm gracefully" do
      jwt.instance_variable_set(:@algorithm, nil)

      # Should still be able to get a signing key
      expect(jwt.signing_key).to be_present
    end

    it "handles nil expiration" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.expires_at = nil

      expect(jwt).to be_valid
      token = jwt.token

      decoded = JWT.decode(token, nil, false)
      expect(decoded[0]["exp"]).to be_nil
    end

    it "handles tokens with missing optional claims" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.subject = nil
      jwt.nonce = nil

      expect(jwt).to be_valid
    end

    it "preserves JWT ID uniqueness" do
      jwt1 = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt2 = described_class.new(algorithm: "HS256", signing_key: hmac_key)

      expect(jwt1.jwt_id).not_to eq(jwt2.jwt_id)
    end

    it "handles large payloads" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.body["large_data"] = "x" * 10_000

      expect(jwt).to be_valid
      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[0]["large_data"].length).to eq(10_000)
    end

    it "handles special characters in claims" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.body["special"] = "Hello\nWorld\t💎"

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[0]["special"]).to eq("Hello\nWorld\t💎")
    end

    it "validates tokens even when iat equals exp" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      now = Time.current
      jwt.issued_at = now
      jwt.expires_at = now

      expect(jwt).not_to be_valid
      expect(jwt.errors[:expires_at]).to include("must be after issued_at")
    end

    it "allows valid temporal ordering" do
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.issued_at = 1.hour.ago
      jwt.not_before = 30.minutes.ago
      jwt.expires_at = 1.hour.from_now

      expect(jwt).to be_valid
    end
  end

  describe "hash accessor behavior" do
    it "supports string keys for body" do
      jwt.body["custom"] = "value"

      expect(jwt.body["custom"]).to eq("value")
    end

    it "supports string keys for header" do
      jwt.header["custom"] = "value"

      expect(jwt.header["custom"]).to eq("value")
    end
  end

  describe "nonce handling" do
    it "sets and retrieves nonce" do
      jwt.nonce = "test_nonce_123"

      expect(jwt.nonce).to eq("test_nonce_123")
      expect(jwt.body["nonce"]).to eq("test_nonce_123")
    end

    it "includes nonce in token" do
      jwt.nonce = "test_nonce"

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[0]["nonce"]).to eq("test_nonce")
    end
  end

  describe "claim_type handling" do
    it "sets and retrieves claim_type in header" do
      jwt.claim_type = "xivauth.test"

      expect(jwt.claim_type).to eq("xivauth.test")
      expect(jwt.header["cty"]).to eq("xivauth.test")
    end

    it "includes claim_type in token" do
      jwt.claim_type = "xivauth.test"

      token = jwt.token
      decoded = JWT.decode(token, nil, false)

      expect(decoded[1]["cty"]).to eq("xivauth.test")
    end
  end

  describe "integration scenarios" do
    it "generates and validates a complete OAuth-style token" do
      app = FactoryBot.create(:client_application)

      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.subject = "user_123"
      jwt.audience = app
      jwt.issued_at = Time.current
      jwt.expires_at = 1.hour.from_now
      jwt.body["scope"] = "read write"

      expect(jwt).to be_valid
      token = jwt.token

      decoded = JWT.decode(token, nil, false)
      expect(decoded[0]["sub"]).to eq("user_123")
      expect(decoded[0]["aud"]).to eq("https://xivauth.net/applications/#{app.id}")
      expect(decoded[0]["scope"]).to eq("read write")
    end

    it "generates and validates an OBO token" do
      azp_app = FactoryBot.create(:client_application)
      aud_app = FactoryBot.create(:client_application)
      aud_app.obo_authorizations << azp_app

      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.subject = "user_456"
      jwt.audience = aud_app
      jwt.authorized_party = azp_app
      jwt.expires_in = 30.minutes

      expect(jwt).to be_valid
      token = jwt.token

      decoded = JWT.decode(token, nil, false)
      expect(decoded[0]["azp"]).to eq("https://xivauth.net/applications/#{azp_app.id}")
      expect(decoded[0]["aud"]).to eq("https://xivauth.net/applications/#{aud_app.id}")
    end

    it "handles key rotation scenario" do
      # Create token with one key
      jwt = described_class.new(algorithm: "HS256", signing_key: hmac_key)
      jwt.subject = "user_789"
      jwt.expires_in = 1.hour
      token = jwt.token

      # Token should be valid even if new keys are added (simulate key rotation)
      FactoryBot.create(:jwt_signing_keys_hmac)

      # Verify token can be decoded
      decoded = JWT.decode(token, nil, false)
      expect(decoded[0]["sub"]).to eq("user_789")
      expect(decoded[1]["kid"]).to eq(hmac_key.name)
    end
  end
end
