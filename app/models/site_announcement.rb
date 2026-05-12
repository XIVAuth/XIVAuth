class SiteAnnouncement < ApplicationRecord
  scope :active, -> { where("start_date >= ? AND (end_date IS NULL OR end_date < ?)", Time.current) }
end
