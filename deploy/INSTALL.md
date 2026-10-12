# Install custom SIETConnect on an existing BigBlueButton server

Run the installer **on the target BBB server**, not on the local Omarchy test workstation. It uses the native server's existing HTTPS URL and API secret, and builds `MarkusRK18/Custom-greenlight` main. Docker Compose v2, git, Python 3 and curl must already be installed. The script does not install another BBB server or use the privileged development container.

Download and inspect the script:

```sh
curl -fL https://raw.githubusercontent.com/MarkusRK18/Custom-greenlight/main/scripts/install-custom-greenlight.sh -o install-custom-greenlight.sh
bash install-custom-greenlight.sh --help
```

To update an existing custom installation, download this script again and rerun
it with the same `--greenlight-dir` and `--public-url` arguments. It fetches the
latest `main`, rebuilds the portal, and applies the persistent session analytics
migration while preserving existing users, meetings and saved session history.
It verifies the analytics database schema after migrating. Both native BBB nginx
include directories (`/etc/bigbluebutton/nginx` and `/usr/share/bigbluebutton/nginx`)
are supported. The prerequisite check also verifies that BBB's event processing
services are active; the installer never restarts BBB services automatically.
If the check reports event recording disabled, update `disableRecordingDefault`
to `false` in the BBB web override and reload BBB web during a maintenance window.

## Replace existing Greenlight v3

Locate the current Compose directory (often `/root/greenlight-v3` or the installing user's `~/greenlight-v3`). Replace the hostname and directory below:

```sh
sudo bash install-custom-greenlight.sh \
  --greenlight-dir /root/greenlight-v3 \
  --public-url https://bbb.example.com \
  --check

sudo bash install-custom-greenlight.sh \
  --greenlight-dir /root/greenlight-v3 \
  --public-url https://bbb.example.com
```

This mode requires a **Greenlight v3** installation, a PostgreSQL service, a Redis service, and `.env` containing `DATABASE_URL` and `SECRET_KEY_BASE`. If service names differ, supply `--app-service`, `--postgres-service` and `--redis-service`. The public URL's path must match the existing `RELATIVE_URL_ROOT` (omit the path for a root installation). Existing nginx routing and HTTPS certificates remain in place.

The installer builds first, stops only the Greenlight app, backs up its PostgreSQL database and mounted uploads, then runs the custom migrations and starts the replacement. BBB meetings continue running, but Greenlight login/meeting creation is briefly unavailable. It preserves the existing `.env`, database/storage mounts, SMTP settings, and secret key. A generated Compose override selects the custom image and BBB credentials. No database volume is deleted.

Meeting descriptions are saved in the database (up to 5,000 characters), editable
in creation and Settings, and shown on the meeting page and in future saved
analytics. Visible Greenlight labels use Meeting/Meetings and SIETConnect.
Internal API routes and translation keys retain their compatible names.

All `siet.ac.in` accounts become administrators. New institutional accounts activate without verification emails. Older accounts in other domains stay in the database but cannot sign in under this policy. Existing rooms without a schedule must be scheduled in room settings before starting them.

## BBB installed without Greenlight, or keep old Greenlight alongside the new portal

```sh
sudo bash install-custom-greenlight.sh --fresh \
  --public-url https://bbb.example.com/connect
```

Fresh mode uses a separate database and upload volume, port `127.0.0.1:5051`, and `/connect` routing on the BBB domain's existing HTTPS nginx virtual host. Use `--port` if 5051 is occupied. It adds a managed nginx snippet and validates nginx before reloading. It does not replace the old portal or move old accounts. Sign up at `/connect/signup` using a `siet.ac.in` address; that account becomes Administrator. No default password is created.

## Manage the installed portal

Default installer directory: `/opt/sietconnect`. For fresh mode the original Compose directory is `/opt/sietconnect/portal`; in upgrade mode use the original Greenlight directory.

```sh
docker compose --project-directory /root/greenlight-v3 \
  --env-file /root/greenlight-v3/.env \
  --env-file /opt/sietconnect/installer.env \
  -f /root/greenlight-v3/docker-compose.yml \
  -f /opt/sietconnect/custom.override.json ps
```

Use the same command prefix with `logs --tail 100 greenlight-v3`, `stop greenlight-v3`, or `up -d greenlight-v3`. Always include the override; using the original Compose file alone would select the upstream image again. Rerunning the installer fetches the selected revision and rebuilds. Keep `/opt/sietconnect/installer.env` and backups private.

The script verifies BBB authentication before stopping the portal and checks the public Greenlight health endpoint after deployment. Native BBB client settings (default PDF, client title and drawing tools) are separate from Greenlight: apply the server settings described in `SRI_SHAKTHI_SETUP.md` if the target server still shows its original welcome slide. BBB service restarts should be scheduled outside active meetings.

## Empty analytics history on an installed server

Run the safe diagnostic on the target Ubuntu server and share its output:

```sh
curl -fL https://raw.githubusercontent.com/MarkusRK18/Custom-greenlight/main/scripts/diagnose-analytics.sh -o diagnose-analytics.sh
sudo bash diagnose-analytics.sh
```

It checks event processing, retention, callback delivery to the public hostname,
and callback log summaries without printing secrets or participant data. If the
server cannot reach its own public hostname, resolve DNS/routing/TLS first.
Only newly started meetings request the custom callback; installing the portal
cannot recreate analytics from old sessions whose events have been discarded.
Branding updates alter HTML5 locales and client title settings; reload HTML5
services during a maintenance window if cached settings still show the old title.
Clear browser cache with Ctrl+Shift+R. Native analytics tabs now have an explicit
college favicon with a versioned asset URL.

## Recovery

Backups live in `/opt/sietconnect/backups/<UTC timestamp>/`: `database.dump`, `storage.tar.gz`, original `.env`/Compose file, and generated deployment configuration. If an upgrade fails, the script reports this directory. Database migrations change account roles and some cannot be reversed, so do not run `db:rollback` as a substitute for restoring the backup.

To restore, stop the custom app, restore `database.dump` to the original PostgreSQL database using `pg_restore --clean --if-exists`, restore the storage archive into the original mounted storage directory, and start the original Compose app without the custom override. Use the original database name and PostgreSQL account from that installation. Keep the failed migration stopped until the restore is complete. The script never automatically restores or discards a database.

Validation performed during development: shell/Python syntax and generated Docker Compose configuration. Installation on your remote BBB server still needs to be run; it has not been executed against that server.
# College logo assets

The meeting page includes an Analytics tab. New sessions request `keepEvents`
and an authenticated analytics callback. BBB's recording/event processing
services must be running for results to arrive after the meeting ends.
Previously completed meetings have no saved analytics to import automatically.
The Analytics tab now lists saved sessions separately, with date/time, start,
end, duration and participant count. Clicking the date opens that session's
stored dashboard. Existing Greenlight analytics are migrated into this history;
repeated or delayed callbacks do not overwrite other sessions. The history is
stored in PostgreSQL and included in the installer's database backup.
Saved dashboards display the full overview columns, participant join/leave
times, connection bars, ended/offline status, last-updated time, download and
Help. Metrics absent from BBB's callback (for example webcam time, annotations,
shared notes or activity score on some versions) display `N/A`, not zero.
Unlimited time uses BBB duration zero; hosts can still end meetings manually.

The installer includes the college logo, favicon, and Apple touch icons from
the repository. It installs a dedicated `/sietconnect-assets/logo.png` route on
the existing BBB hostname and uses it for both Greenlight and meeting branding.
Rerun the updated installer with your original arguments to apply this change
to an existing deployment. No separate logo download or upload is needed.

To install only the native BBB logo files and icons from a checked-out repository:

```bash
sudo bash scripts/install-college-assets.sh
```

This reloads nginx and keeps backups under `/var/backups/sietconnect-assets.*`.
It does not restart BBB or alter functional microphone/headphone icons.
Meeting logos apply to newly started meetings after the portal upgrade. If the
native BBB client has its branding area disabled, enable
`public.app.branding.displayBrandingArea: true` in
`/etc/bigbluebutton/bbb-html5.yml` and restart the HTML5 services during maintenance.
