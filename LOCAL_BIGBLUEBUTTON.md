# BigBlueButton local testing

The BigBlueButton Docker development image referenced by https://github.com/bigbluebutton/docker-dev was downloaded and started. Its authenticated HTTPS API passed verification, and the portal was connected. Real meeting/client verification was interrupted by reboot. A snapshot boot temporarily hid the installed containers; the workstation has since returned to its normal Omarchy boot, and Greenlight was verified to return HTTP 200 again. Use the normal boot for continued installation and verification.

The Ubuntu container can expose console login services when privileged. The startup script now masks console/getty services, and the Compose configuration disables automatic restart. Apply the Compose configuration after returning to the normal boot. The user requested using available disk space for a reduced local test rather than waiting for the standard 50 GiB VM setup.

## Local layout

- Existing Sri Shakthi portal: http://localhost:5050
- Planned meeting server: https://bbb.srishakthi.test
- Private Docker bridge: sri-shakthi-bbb-test, 172.30.50.0/24
- Meeting server address: 172.30.50.10
- Limits: 4 CPU cores, 8 GiB RAM, up to 2 GiB additional swap.
- Recording is disabled server-side. The recording-processing services are masked.
- The presentation starts hidden and no default welcome deck is uploaded. Drawing tools remain available after the presenter opens/uploads a presentation. Session details do not open automatically.
- Document conversion through LibreOffice is omitted; the host Docker socket is not mounted.
- The development container uses systemd and privileged mode, as required by the upstream development setup. It publishes no host ports and is intended for testing on this machine.

The local CA and keys are in ignored local-bbb/ files. /etc/hosts contains the test hostname. The CA is trusted through the host certificate store and the existing Chromium NSS database. Host and Chromium certificate backups are under local-bbb/private/.

## Start and stop

```sh
docker compose -f compose.bbb-local.yml up -d
# Connect the portal only after the server API is healthy:
python3 scripts/connect-local-bbb.py
docker compose --env-file .env.local -f compose.local.yml -f compose.portal-bbb.yml up -d portal
# Server health:
python3 scripts/verify-local-bbb.py
docker exec sri-shakthi-bbb-test bbb-conf --status
# Stop the meeting server without removing its writable configuration:
docker compose -f compose.bbb-local.yml stop
```

Keep at least 8 GiB free for this reduced setup (`bash scripts/check-local-bbb-space.sh`). Stopping preserves the test container state. Recreating the meeting-server container reruns the local settings script and restores configuration from the development image; no recording data needs to be retained.

The existing portal database and user accounts remain in their separate persistent volumes. The API secret is generated locally, stored privately, and copied to .env.local after verification. Do not share the secret or join URLs.

Authenticated HTTPS API verification passed before reboot. Meeting-start, client-loading and media checks remain pending; the portal/server need to be checked again after returning to the normal boot.
