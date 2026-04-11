class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Override implicit column order so we get nice formatting despite using UUIDs.
  def self.implicit_order_column
    original = super
    return original if original

    begin
      "created_at" if column_names.include?("created_at")
    rescue
      # nop - we don't care if we fail because of column_names problems.
      nil
    end
  end
end
