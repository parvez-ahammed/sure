class CreateBackupCredentials < ActiveRecord::Migration[7.2]
  def change
    create_table :backup_credentials, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :provider_type, null: false
      t.text   :access_token
      t.text   :refresh_token
      t.datetime :token_expires_at
      t.string :scope
      t.string :google_account_email
      t.string :folder_id
      t.string :folder_name
      t.datetime :verified_at
      t.timestamps
    end

    add_index :backup_credentials, :provider_type, unique: true
  end
end
