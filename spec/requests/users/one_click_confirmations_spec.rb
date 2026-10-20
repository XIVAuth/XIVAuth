require "rails_helper"

RSpec.describe "POST /auth/register/confirm (one-click confirmation)" do
  # Request specs disable CSRF checks by default; turn them on to match what Gmail's POST actually hits.
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  let(:user) { FactoryBot.create(:user, confirmed_at: nil) }
  # Devise stores confirmation tokens as-is, so the stored value is also what the email link carries.
  let!(:token) do
    Devise.friendly_token.tap do |t|
      user.update_columns(confirmation_token: t, confirmation_sent_at: Time.current)
    end
  end

  it "confirms the user without a session or CSRF token" do
    post user_one_click_confirmation_path(confirmation_token: token)

    expect(response).to have_http_status(:ok)
    expect(user.reload).to be_confirmed
  end

  it "treats an already-confirmed token as success" do
    post user_one_click_confirmation_path(confirmation_token: token)
    post user_one_click_confirmation_path(confirmation_token: token)

    expect(response).to have_http_status(:ok)
  end

  it "rejects an unknown token" do
    post user_one_click_confirmation_path(confirmation_token: "nope")

    expect(response).to have_http_status(:bad_request)
    expect(user.reload).not_to be_confirmed
  end

  it "applies a pending email change" do
    user.update_columns(confirmed_at: Time.current, unconfirmed_email: "changed@example.test")

    post user_one_click_confirmation_path(confirmation_token: token)

    expect(response).to have_http_status(:ok)
    expect(user.reload.email).to eq("changed@example.test")
  end
end
