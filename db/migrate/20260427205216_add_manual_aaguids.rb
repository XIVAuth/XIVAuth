class AddManualAaguids < ActiveRecord::Migration[8.1]
  def change
    add_column :webauthn_device_classes, :manual, :boolean, default: false
  end
end
