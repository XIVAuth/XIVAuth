require "rails_helper"

RSpec.describe Attachment::GenerateDefaultAvatarJob do
  include ActiveJob::TestHelper

  let(:tiny_png) do
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
  end

  def stub_dicebear(status: 200, body: tiny_png)
    response = instance_double(Faraday::Response, success?: (200..299).cover?(status), status: status, body: body)
    allow(Faraday).to receive(:get).and_return(response)
  end

  it "fetches the record's default avatar and persists it as the icon" do
    stub_dicebear
    team = FactoryBot.create(:team)
    clear_enqueued_jobs

    described_class.perform_now("Team", team.id, "icon")

    expect(Faraday).to have_received(:get).with(team.default_icon_url)
    expect(team.reload.icon).to be_present
    expect(team.icon.file.read).to eq(tiny_png)
  end

  it "does nothing if the attachment is already present" do
    stub_dicebear
    team = FactoryBot.create(:team)
    described_class.perform_now("Team", team.id, "icon")
    original_attachment_id = team.reload.icon.id

    expect(Faraday).not_to receive(:get)

    described_class.perform_now("Team", team.id, "icon")

    expect(team.reload.icon.id).to eq(original_attachment_id)
  end

  it "does nothing if the record no longer exists" do
    stub_dicebear

    expect(Faraday).not_to receive(:get)

    expect { described_class.perform_now("Team", SecureRandom.uuid, "icon") }.not_to raise_error
  end

  it "schedules a retry via retry_on and leaves no partial icon on a non-success response" do
    stub_dicebear(status: 500, body: "")
    team = FactoryBot.create(:team)
    clear_enqueued_jobs

    # retry_on rescues internally and re-enqueues, so perform_now itself doesn't raise.
    expect { described_class.perform_now("Team", team.id, "icon") }.not_to raise_error

    expect(team.reload.icon).to be_nil
    expect(enqueued_jobs.size).to eq(1)
  end

  it "retries instead of failing outright when rate limited" do
    stub_dicebear(status: 429, body: "")
    team = FactoryBot.create(:team)
    clear_enqueued_jobs

    expect { described_class.perform_now("Team", team.id, "icon") }.not_to raise_error

    expect(team.reload.icon).to be_nil
    expect(enqueued_jobs.size).to eq(1)
  end
end
