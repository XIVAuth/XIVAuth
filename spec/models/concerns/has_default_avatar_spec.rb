require "rails_helper"

RSpec.describe HasDefaultAvatar do
  include ActiveJob::TestHelper

  # Exercised through the two real includers rather than an anonymous class,
  # since generate_default_avatar leans on has_upload_attachment's config and
  # AR callbacks being present on the including model.
  describe "Team" do
    it "builds a default_icon_url from the team's name" do
      team = FactoryBot.build(:team, name: "Ferrymen")

      expect(team.default_icon_url).to eq(
        "https://api.dicebear.com/10.x/initials/png?seed=Ferrymen&backgroundType=gradientLinear"
      )
    end

    it "enqueues avatar generation on create when no icon was uploaded" do
      team = FactoryBot.build(:team)

      # team.id isn't known until after save! (DB-generated UUID default), so
      # assert the args via a block evaluated once the job is actually enqueued.
      expect { team.save! }.to have_enqueued_job(Attachment::GenerateDefaultAvatarJob)
        .with { |*args| expect(args).to eq(["Team", team.id, "icon"]) }
    end

    it "does not enqueue avatar generation when an icon was uploaded at creation" do
      team = FactoryBot.build(:team)
      team.icon = Rack::Test::UploadedFile.new(
        StringIO.new(tiny_png), "image/png", original_filename: "icon.png"
      )

      expect { team.save! }.not_to have_enqueued_job(Attachment::GenerateDefaultAvatarJob)
    end

    it "does not re-enqueue avatar generation on subsequent updates" do
      team = FactoryBot.create(:team)
      clear_enqueued_jobs

      expect { team.update!(name: "Renamed") }.not_to have_enqueued_job(Attachment::GenerateDefaultAvatarJob)
    end
  end

  describe "ClientApplication" do
    it "builds a default_icon_url from the app's name" do
      app = FactoryBot.build(:client_application, name: "My App")

      expect(app.default_icon_url).to eq(
        "https://api.dicebear.com/10.x/initials/png?seed=My+App&backgroundType=gradientLinear"
      )
    end

    it "enqueues avatar generation on create when no icon was uploaded" do
      app = FactoryBot.build(:client_application, owner: FactoryBot.create(:user, :developer))

      expect { app.save! }.to have_enqueued_job(Attachment::GenerateDefaultAvatarJob)
        .with { |*args| expect(args).to eq(["ClientApplication", app.id, "icon"]) }
    end
  end

  def tiny_png
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
  end
end
