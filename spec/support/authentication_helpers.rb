module AuthenticationHelpers
  # Helper to sign in a user in request specs
  # This actually performs the login request to set up the session properly
  def true_sign_in(user, password: nil)
    # Use provided password or try to get it from the user object
    pwd = password || user.instance_variable_get(:@password) || user.password

    post user_session_path, params: {
      user: {
        email: user.email,
        password: pwd
      }
    }
  end

  # Helper to sign out a user in request specs
  def true_sign_out
    delete destroy_user_session_path
  end

  def build_fake_webauthn(origin)
    client = WebAuthn::FakeClient.new(origin, encoding: :base64url)
    create_options = WebAuthn::Credential.options_for_create(user: { id: "fake_id", name: "fake_name" })

    client.create(challenge: create_options.challenge)
    client
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
