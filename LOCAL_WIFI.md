# Connect phones and laptops over the same Wi-Fi

This is an optional mode for the local development stack. Run it on the host
computer while no meetings are active:

```sh
bash scripts/enable-local-wifi.sh
# If the default route is not Wi-Fi, specify the computer's Wi-Fi IPv4 address:
bash scripts/enable-local-wifi.sh 192.168.1.50
```

The script prints the actual addresses to use. It reuses the existing local CA,
adds the Wi-Fi IP to the server certificate, preserves Docker recording volumes,
and recreates the local containers with LAN settings. Backups of certificates and
previous LAN settings are stored under ignored `local-bbb/private/wifi-backups/`.
If host UFW is active, administrator authorization is requested to add rules
limited to the selected Wi-Fi subnet and the local BBB bridge. Existing firewall
rules are preserved; backups are saved in `/var/backups/sietconnect-wifi.*`.
The BBB container's own firewall also permits the portal and setup ports for
that subnet. Existing local recording links are updated to the Wi-Fi address.
The installer for a native public BBB server does not need this local mode.

## Set up each Android phone or laptop

1. Connect the device to the same Wi-Fi as the host computer.
2. Open `http://HOST-WIFI-IP:8080`. This page serves setup instructions and the
   public test CA certificate only; no login or private keys are served there.
3. Download the CA certificate and compare its SHA-256 fingerprint with the one
   printed on the host computer.
4. Android: open Settings → Security → Encryption & credentials → Install a
   certificate → CA certificate. Select the downloaded SIETConnect certificate.
   Menu names vary between phones. This is a CA certificate for HTTPS; choosing
   the separate Wi-Fi certificate option does not establish browser trust.
5. Laptops: import this CA into the trusted certificate authorities used by the
   browser. Windows uses Trusted Root Certification Authorities; macOS uses
   Keychain Access. Firefox may require importing it in its own certificate
   settings.
6. Open `https://HOST-WIFI-IP:8443`, sign in or open a meeting invitation, and
   allow the browser to use the microphone and camera. Meeting windows use
   `https://HOST-WIFI-IP` on port 443.

Install this test CA only on devices used for local testing. Existing devices
that already trust it do not need to install it again. Keep the host computer
awake. If DHCP changes its Wi-Fi IP, rerun the setup script and use the new
address; the CA stays the same.

## Start the Wi-Fi configuration again

```sh
docker compose --env-file local-bbb/lan.env \
  -f compose.bbb-local.yml -f compose.bbb-lan.yml up -d

docker compose --env-file .env.local --env-file local-bbb/lan.env \
  -f compose.local.yml -f compose.portal-bbb.yml -f compose.portal-lan.yml up -d portal
```

Use these overrides when starting Wi-Fi mode. Starting with the base Compose
files alone switches back to local-only access. To do that intentionally, end
active meetings first, then run:

```sh
docker compose -f compose.bbb-local.yml up -d
docker compose --env-file .env.local -f compose.local.yml -f compose.portal-bbb.yml up -d portal
```

The LAN mode binds TCP 443, 8443 and 8080 and UDP 16384–16447 and 20000–20127
only to the selected private IPv4 address. The smaller media ranges suit this
limited local test server. Redis and PostgreSQL stay on private Docker networks.

If another device cannot open the setup page, confirm the IP and Wi-Fi first.
Campus or guest Wi-Fi may isolate devices; the network administrator must allow
device-to-device connections. If pages load but audio/cameras fail, check the
device's CA trust, microphone permissions and the LAN UDP ranges.

Server-side HTTPS and authenticated API checks do not replace testing a real
meeting from a second device on the Wi-Fi network.
