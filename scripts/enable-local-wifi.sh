#!/usr/bin/env bash
# Opt-in LAN access for the isolated local portal and meeting server.
set -Eeuo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
[[ $# -le 1 ]] || { echo 'Usage: bash scripts/enable-local-wifi.sh [LAN_IPV4]' >&2; exit 1; }
lan_ip=$(python3 - "${1:-}" <<'PY'
import ipaddress,json,subprocess,sys
addresses=json.loads(subprocess.check_output(['ip','-j','-4','address','show'],text=True))
available={a['local'] for interface in addresses for a in interface.get('addr_info',[]) if a.get('scope')=='global'}
candidate=sys.argv[1]
if not candidate:
 routes=json.loads(subprocess.check_output(['ip','-j','-4','route','show','default'],text=True))
 if not routes: raise SystemExit('No default network route. Connect to Wi-Fi first.')
 dev=sorted(routes,key=lambda r:r.get('metric',0))[0]['dev']
 candidates=[a['local'] for interface in addresses if interface['ifname']==dev for a in interface.get('addr_info',[]) if a.get('scope')=='global']
 if len(candidates)!=1: raise SystemExit('Supply the Wi-Fi IPv4 address explicitly.')
 candidate=candidates[0]
address=ipaddress.IPv4Address(candidate)
if str(address) not in available or not address.is_private or address.is_loopback or address.is_link_local:
 raise SystemExit('Use a private IPv4 address assigned to this computer.')
print(address)
PY
)
lan_subnet=$(python3 - "$lan_ip" <<'PY'
import ipaddress,json,subprocess,sys
interfaces=json.loads(subprocess.check_output(['ip','-j','-4','address','show'],text=True))
address=next(a for i in interfaces for a in i.get('addr_info',[]) if a.get('local')==sys.argv[1])
print(ipaddress.IPv4Network(f'{sys.argv[1]}/{address["prefixlen"]}',strict=False))
PY
)
for file in .env.local local-bbb/private/sri-shakthi-local-ca.key local-bbb/certs/privkey.pem local-bbb/certs/sri-shakthi-local-ca.crt; do
  [[ -s $file ]] || { echo "Missing local prerequisite: $file. Set up the local BBB stack first." >&2; exit 1; }
done
docker info >/dev/null
# Refuse to recreate an old ephemeral container before it has been backed up.
storage_type=$(docker inspect sri-shakthi-bbb-test --format '{{range .Mounts}}{{if eq .Destination "/var/bigbluebutton"}}{{.Type}}{{end}}{{end}}')
[[ $storage_type == volume ]] || { echo 'BBB recording storage is not persistent. Back up the container recordings before enabling Wi-Fi.' >&2; exit 1; }
python3 scripts/verify-local-bbb.py --require-idle
backup_dir="local-bbb/private/wifi-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
cp -a local-bbb/certs "$backup_dir/"
[[ ! -f local-bbb/lan.env ]] || cp -a local-bbb/lan.env "$backup_dir/"
printf 'LOCAL_BBB_LAN_IP=%s\nLOCAL_BBB_LAN_SUBNET=%s\n' "$lan_ip" "$lan_subnet" > local-bbb/lan.env
bbb=(docker compose --env-file local-bbb/lan.env -f compose.bbb-local.yml -f compose.bbb-lan.yml)
portal=(docker compose --env-file .env.local --env-file local-bbb/lan.env -f compose.local.yml -f compose.portal-bbb.yml -f compose.portal-lan.yml)
"${bbb[@]}" config --quiet
"${portal[@]}" config --quiet
if systemctl is-active --quiet ufw; then
  if [[ -t 0 ]]; then
    sudo /usr/bin/python3 "$project_dir/scripts/configure-local-wifi-firewall.py" "$lan_ip"
  else
    pkexec /usr/bin/python3 "$project_dir/scripts/configure-local-wifi-firewall.py" "$lan_ip"
  fi
fi
trap 'printf "Wi-Fi setup stopped. Certificate/configuration backup: %s. Inspect the failed step before retrying.\n" "$backup_dir" >&2' ERR
# Reuse the existing CA: devices already trusting it keep working.
openssl req -new -key local-bbb/certs/privkey.pem -subj '/CN=bbb.srishakthi.test' -out "$backup_dir/lan.csr"
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:bbb.srishakthi.test,IP:%s\n' "$lan_ip" > "$backup_dir/lan.ext"
openssl x509 -req -sha256 -days 365 -in "$backup_dir/lan.csr" \
  -CA local-bbb/certs/sri-shakthi-local-ca.crt -CAkey local-bbb/private/sri-shakthi-local-ca.key \
  -CAcreateserial -extfile "$backup_dir/lan.ext" -out local-bbb/certs/bbb.srishakthi.test.crt
cat local-bbb/certs/bbb.srishakthi.test.crt local-bbb/certs/sri-shakthi-local-ca.crt > local-bbb/certs/fullchain.pem
chmod 644 local-bbb/certs/bbb.srishakthi.test.crt local-bbb/certs/fullchain.pem local-bbb/certs/sri-shakthi-local-ca.crt
"${bbb[@]}" up -d
"${portal[@]}" up -d --no-build portal
# Wait for the HTTPS portal and authenticated meeting API without exposing secrets.
python3 scripts/verify-local-wifi.py "$lan_ip"
"${portal[@]}" exec -T -e LOCAL_BBB_LAN_IP="$lan_ip" portal bundle exec rails runner '
require "ipaddr"
updated = 0
Format.find_each do |format|
  uri = URI.parse(format.url)
  local = uri.host == "bbb.srishakthi.test" || (IPAddr.new(uri.host).private? rescue false)
  next unless local && uri.scheme == "https"
  next if uri.host == ENV.fetch("LOCAL_BBB_LAN_IP")
  uri.host = ENV.fetch("LOCAL_BBB_LAN_IP")
  format.update!(url: uri.to_s)
  updated += 1
end
puts "Updated #{updated} local recording format links for Wi-Fi access."
'
printf '\nOn each Wi-Fi device, open http://%s:8080 and install the local CA certificate.\nThen open https://%s:8443\n' "$lan_ip" "$lan_ip"
openssl x509 -in local-bbb/certs/sri-shakthi-local-ca.crt -noout -sha256 -fingerprint
printf 'Keep the host computer awake. Rerun this script if its Wi-Fi IP changes.\n'
