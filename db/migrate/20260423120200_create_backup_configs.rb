class CreateBackupConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :backup_configs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.boolean :enabled, null: false, default: false
      t.string  :frequency, null: false, default: "daily"
      t.integer :retention_days, null: false, default: 30
      t.integer :hour_utc, null: false, default: 2
      t.integer :key_version, null: false, default: 1
      t.timestamps
    end
  end
end
