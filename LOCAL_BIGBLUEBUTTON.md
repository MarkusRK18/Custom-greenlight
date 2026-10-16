# BigBlueButton local testing

This isolated setup uses the BigBlueButton Docker development image referenced by https://github.com/bigbluebutton/docker-dev. The portal at `localhost:5050` needs this separate meeting server before meetings or recordings can work. The private certificates, API secret, and container are recreated locally and are not stored in Git.

The Ubuntu container can expose console login services when privileged. The startup script now masks console/getty services, and the Compose configuration disables automatic restart. Apply the Compose configuration after returning to the normal boot. The user requested using available disk space for a reduced local test rather than waiting for the standard 50 GiB VM setup.

## Local layout

- Existing Sri Shakthi portal: http://localhost:5050
- Planned meeting server: https://bbb.srishakthi.test
- Private Docker bridge: sri-shakthi-bbb-test, 172.30.50.0/24
- Meeting server address: 172.30.50.10
- Limits: 4 CPU cores, 8 GiB RAM, up to 2 GiB additional swap.
- Recording is enabled for testing. Moderators can start and stop recording, and the recording-processing services are enabled.
- Raw and published recordings use Docker volumes so restarting the local test container preserves them. The combined video workflow publishes shared slides, cameras, screen share and meeting audio when those streams are present.
- The presentation starts hidden and no default welcome deck is uploaded. Drawing tools remain available after the presenter opens/uploads a presentation. Session details do not open automatically.
- Document conversion through LibreOffice is omitted; the host Docker socket is not mounted.
- The development container uses systemd and privileged mode, as required by the upstream development setup. It publishes no host ports and is intended for testing on this machine.

The local CA and keys live in ignored `local-bbb/` files. Generate them with `bash scripts/setup-local-bbb.sh`. Configure the test hostname and CA trust with `sudo python3 scripts/configure-local-bbb-host.py`, then trust the CA in Chromium with `bash scripts/trust-local-bbb-browser.sh`.

## Start and stop

```sh
bash scripts/setup-local-bbb.sh
sudo python3 scripts/configure-local-bbb-host.py
bash scripts/trust-local-bbb-browser.sh
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

Keep at least 8 GiB free for this reduced setup (`bash scripts/check-local-bbb-space.sh`). Stopping preserves the test container state. Recreating the meeting-server container reruns the local settings script and restores configuration from the development image. Recordings made in this disposable development container are lost if it is recreated.

The existing portal database and user accounts remain in their separate persistent volumes. The API secret is generated locally, stored privately, and copied to .env.local after verification. Do not share the secret or join URLs.

For a recording, open the room's Settings and enable **Allow room to be recorded** before starting a new meeting. Recording starts automatically when the host joins the new meeting; moderators may still pause or resume it. Join the meeting audio with a microphone, and upload a presentation or share a screen or camera to capture those streams. End the meeting and wait for the recording processor to publish playback. The room's Recordings tab then shows presentation and combined video formats. The participant list shows total talk time once the analytics callback arrives. Playback identifies a speaker at the recorded time if BBB captured `ParticipantTalkingEvent` events. A meeting with no captured audio, slides, camera or screen share shows an explicit notice instead of silently appearing blank.
