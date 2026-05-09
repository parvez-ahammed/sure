class CreateBackupRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :backup_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :status, null: false, default: "pending"
      t.string   :trigger, null: false, default: "scheduled"
      t.datetime :started_at
      t.datetime :completed_at
      t.text     :error_message
      t.string   :filename
      t.string   :remote_file_id
      t.string   :provider_type
      t.bigint   :byte_size
      t.string   :plaintext_sha256
      t.integer  :key_version
      t.binary   :salt
      t.integer  :duration_ms
      t.timestamps
    end

    add_index :backup_runs, :created_at
    add_index :backup_runs, :status
  end
end
