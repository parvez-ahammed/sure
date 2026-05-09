class AddDestinationToFamilyExports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_exports, :destination, :string, null: false, default: "local_download"
    add_column :family_exports, :remote_file_id, :string
    add_column :family_exports, :remote_provider_type, :string
  end
end
