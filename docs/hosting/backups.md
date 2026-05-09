# Self-hosted backups

> Encrypted automated database backups uploaded to Google Drive over OAuth. Self-hosted only.

Sure ships an opt-in, zero-trust backup subsystem for self-hosted deployments. This doc covers setup, the on-disk file format, and the recovery procedure.

## Audience and feature gate

The backup UI is only available when:
- `Rails.application.config.app_mode.self_hosted?` is true, **and**
- the current user is a `super_admin`.

In managed mode the feature is hidden entirely.

## Setup

### One-time: register a Google OAuth client

1. Open https://console.cloud.google.com → create or select a project.
2. APIs & Services → Library → enable **Google Drive API**.
3. APIs & Services → OAuth consent screen
   - User type: **External** (or **Internal** if your org uses Google Workspace)
   - App name: `Sure Backup`, support email = your email
   - Scopes → Add `https://www.googleapis.com/auth/drive.file`
   - Test users → add the Google account you'll connect with (skip if you publish the app)
4. APIs & Services → Credentials → Create Credentials → **OAuth client ID**
   - Application type: **Web application**
   - Authorized redirect URIs:
     - `https://<your-sure-host>/settings/backups/oauth/callback`
     - For local development: `http://localhost:3000/settings/backups/oauth/callback`
5. Copy the **Client ID** and **Client secret**. Set them as environment variables on every web + worker container:

   ```
   BACKUP_GOOGLE_OAUTH_CLIENT_ID=...
   BACKUP_GOOGLE_OAUTH_CLIENT_SECRET=...
   ```

   Restart the app.

### Connect Sure to Google Drive

1. Sign in to Sure as a `super_admin`.
2. Go to **Settings → Backups**.
3. Click **Connect with Google** → grant access.
4. The page now shows your connected email and the folder name (`Sure Backups`).

### Schedule backups

1. Same page, lower section: enable scheduled backups, pick frequency, hour-of-day (UTC), retention days, save.
2. Click **Run backup now** to validate end-to-end. Verify a file appears in the `Sure Backups` folder in your Drive.

### Notes

- The `drive.file` scope means Sure can only read or write files **it created**. It cannot see any of your other Drive content.
- The `Sure Backups` folder is created automatically on the first backup run.
- **Disconnect** revokes the refresh token at Google and clears local tokens. Existing backup files in Drive and the folder itself are not deleted.
- Tokens are AR-encrypted at rest. The encryption key is auto-derived from `SECRET_KEY_BASE` in self-hosted mode.
- If your redirect URI does not exactly match what is registered in Cloud Console, Google rejects the callback with `redirect_uri_mismatch`.

## What gets backed up

A single `pg_dump --format=custom` of the entire application database. This crosses families and includes `users`, `sessions`, and `api_keys`, so the file is *highly* sensitive — that is why it is encrypted before leaving the host.

## File format (`.sbk`)

```
Offset  Len  Field
0       7    Magic "SUREBAK"
7       1    Version (0x01)
8       16   Salt (random, per backup)
24      12   IV   (random, per backup)
36      N    Ciphertext (AES-256-GCM, plaintext is gzipped pg_dump custom format)
end-16  16   GCM auth tag
```

- **Cipher**: AES-256-GCM
- **Compression**: gzip *before* encrypt (encrypt-after-compress; encrypted bytes do not compress)
- **Key derivation**: `PBKDF2-HMAC-SHA1(SECRET_KEY_BASE, salt, 1000 iterations, 32 bytes)` (matches `ActiveSupport::KeyGenerator` defaults)
- **Authenticated data**: the 36-byte header is included as GCM AAD, so any tamper of the header *or* ciphertext fails decryption.

## Recovery

You need three things:
1. The `.sbk` file
2. The `SECRET_KEY_BASE` value the file was encrypted under (or the corresponding `BACKUP_KEY_V<n>` value if you have rotated keys)
3. A `pg_restore` binary whose major version matches the dump (currently 16)

### Decrypt

Use the standalone Ruby script shipped at [`bin/decrypt_backup`](../../bin/decrypt_backup). It has **no Rails or bundler dependency** — only the Ruby stdlib.

```bash
bin/decrypt_backup sure_backup_20260423_020000_v1.sbk "$SECRET_KEY_BASE" > restore.pgdump
```

### Restore into a fresh DB

```bash
createdb sure_production
pg_restore --clean --if-exists --no-owner --no-privileges -d sure_production restore.pgdump
```

## Key rotation

Keys are forward-only. Old backups remain decryptable with the key version they were written under, until you remove that key material.

1. Generate a new strong secret and store it as `BACKUP_KEY_V<next>` in your environment, *or* under `Rails.application.credentials.backup.historical_keys` keyed by integer version.
2. In **Settings → Backups → Encryption key**, click **Rotate to next key version**.
3. Future scheduled and manual backups will be encrypted with the new key.
4. Keep prior `BACKUP_KEY_V<n>` values around for as long as you want their backups to remain decryptable. Removing them is a deliberate, destructive act.

The settings page displays a short SHA-256 fingerprint of the active key — write this down so you can recognize which `SECRET_KEY_BASE` matches a given file.

## Operational notes

- **Disk requirement**: roughly 2× the gzipped database size in `/tmp` during a backup run (one tempfile for raw `pg_dump`, one for gzipped output before upload).
- **`pg_dump` major version mismatch**: jobs abort fast with a clear error rather than upload a possibly-corrupt file. Make sure the worker image's `postgresql-client-<N>` major matches the server.
- **Sidekiq locks**: `Backup::RunJob` and `Backup::CleanupJob` are guarded by `sidekiq-unique-jobs` (`lock: :until_executed, on_conflict: :reject`) so duplicate triggers are dropped.
- **Cleanup safety**: retention deletes are based on the embedded timestamp in the filename (`sure_backup_YYYYMMDD_HHMMSS_v<N>.sbk`), not the provider's `createdTime`. This avoids races with in-flight uploads whose `Backup::Run.remote_file_id` has not been recorded yet.
- **Failure surfacing**: the settings page shows a banner whenever the most recent run failed; details (error class + message) are stored on `Backup::Run`.

## Limitations / known gaps

- Only Google Drive is implemented in Phase 0/1. The provider abstraction (`Backup::Provider::Base`) is built so S3/OneDrive can be added later.
- Plaid investments and Lunchflow do not store pending metadata in `extra` — this is unrelated to backups but called out in `CLAUDE.md`.
- "Verify last backup" only checks file presence + size at the destination. It does not download and decrypt.
