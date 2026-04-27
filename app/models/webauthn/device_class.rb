# frozen_string_literal: true

class Webauthn::DeviceClass < ApplicationRecord
  AAGUID_DATASET = "https://raw.githubusercontent.com/passkeydeveloper/passkey-authenticator-aaguids/refs/heads/main/combined_aaguid.json"

  def self.load_from_dataset
    uri = URI(AAGUID_DATASET)
    response = Net::HTTP.get_response(uri)

    raise "Failed to fetch AAGUID dataset: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    where(manual: true).pluck(:id).each { |id| data.delete(id) }

    transaction do
      # Mark timestamp before upserts
      sync_time = Time.current

      # Convert data to array of records for batch processing
      records = data.map do |aaguid, attributes|
        {
          id: aaguid,
          name: attributes["name"],
          icon_dark: attributes["icon_dark"],
          icon_light: attributes["icon_light"],
          updated_at: sync_time
        }
      end

      # Batch upsert 100 records at a time
      records.each_slice(100) do |batch|
        upsert_all(batch, unique_by: :id)
      end

      # Delete AAGUIDs that weren't updated in this sync (i.e., no longer in dataset)
      # Ignore manual records.
      where("updated_at < ? AND manual = false", sync_time).delete_all
    end
  end
end
