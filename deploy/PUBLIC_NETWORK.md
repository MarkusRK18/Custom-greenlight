# Existing server behind NAT

Run `scripts/configure-public-bbb.py` on the existing native BBB 3 server. This
is a separate network migration tool, not an automatic step of portal upgrades.

```bash
sudo python3 scripts/configure-public-bbb.py \
  --hostname your-server.duckdns.org \
  --public-ip YOUR_PUBLIC_IPV4 --private-ip YOUR_SERVER_LAN_IPV4
```

This inspects the existing HTTPS hostname and configuration and prints a plan.
Use `--apply` to back up the files, configure the mediasoup advertised IPv4 and
FreeSWITCH external addresses, add server-local hostname resolution using the
LAN IP, and restart BBB. Run between meetings. It preserves unrelated SFU keys,
IPv6 entries, existing hosts aliases, nginx listeners, portal data and certificates.
Native YAML must be valid before restarting. The tool refuses invalid YAML.

Add `--update-duckdns` with `--apply` to update public IPv4 DNS using a hidden
token prompt. The token is not saved or passed as a shell argument. Existing DNS
AAAA records are not changed; check that any published IPv6 address is reachable.
If server configuration fails, files are restored; an accepted DNS update is not
rolled back. Backups are stored under `/var/backups/sietconnect-public-bbb.*`.

Configure the router separately:

| Public port | Server destination |
|---|---|
| TCP 443 | LAN server TCP 443 |
| TCP 8445 | LAN server TCP 8445 |
| UDP 16384–32768 | Same ports on LAN server |

Keep TCP 80 available for certificate renewal if your ACME configuration requires
it. The existing port-8445 portal proxy is preserved; the script does not create
an ACME route or configure the router. It opens the listed ports only if UFW is
already active, and never enables UFW automatically. Check other firewalls too.

The server-local hosts entry does not change public DNS or Docker DNS. If the
portal container cannot reach the public hostname due to absent router hairpin
NAT, configure LAN split DNS, or add a Compose `extra_hosts` entry mapping the
BBB hostname to the LAN server IP and recreate the app container. Keep the HTTPS
hostname in the API endpoint so its certificate continues to validate.

After applying, test the HTTPS hostname on mobile data, join a meeting with two
devices, and test both audio and camera. No script on the server alone can verify
or guarantee external UDP forwarding through your router.

Reference: https://docs.bigbluebutton.org/3.0/administration/firewall-configuration/
