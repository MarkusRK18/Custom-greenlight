#!/usr/bin/env bash
# Install tracked college branding on an existing native BBB Ubuntu server.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
assets=/var/www/bigbluebutton-default/assets
snippet=/usr/share/bigbluebutton/nginx/sietconnect-assets.nginx
if grep -Rqs '/etc/bigbluebutton/nginx/' /etc/nginx/sites-enabled; then
  snippet=/etc/bigbluebutton/nginx/sietconnect-assets.nginx
fi
[[ -d $assets && -d ${snippet%/*} ]] || { echo 'Native BBB asset directories are missing.' >&2; exit 1; }
grep -Rqs "${snippet%/*}/" /etc/nginx/sites-enabled || { echo 'BBB nginx includes are not enabled.' >&2; exit 1; }
for file in sri-shakthi-logo.png favicon.ico apple-touch-icon.png apple-touch-icon-precomposed.png sietconnect-theme.css; do
  [[ -s $source_dir/public/$file ]] || { echo "Missing tracked asset: $file" >&2; exit 1; }
done
nginx -t
backup=$(mktemp -d /var/backups/sietconnect-assets.XXXXXXXX)
chmod 700 "$backup"
if [[ -e $snippet ]]; then
  grep -q '# Managed by SIETConnect assets' "$snippet" || { echo 'Unmanaged asset route exists; refusing to overwrite.' >&2; exit 1; }
  cp -a "$snippet" "$backup/route.before"
fi
for file in favicon.ico apple-touch-icon.png apple-touch-icon-precomposed.png; do
  [[ ! -e $assets/$file ]] || cp -a "$assets/$file" "$backup/$file"
done
[[ ! -d $assets/sietconnect ]] || cp -a "$assets/sietconnect" "$backup/"
install -d -m 755 "$assets/sietconnect"
install -m 644 "$source_dir/public/sri-shakthi-logo.png" "$assets/sietconnect/logo.png"
install -m 644 "$source_dir/public/sietconnect-theme.css" "$assets/sietconnect/theme.css"
for file in favicon.ico apple-touch-icon.png apple-touch-icon-precomposed.png; do
  install -m 644 "$source_dir/public/$file" "$assets/sietconnect/$file"
  install -m 644 "$source_dir/public/$file" "$assets/$file"
done
cat > "$snippet" <<'NGINX'
# Managed by SIETConnect assets
location ^~ /sietconnect-assets/ {
  alias /var/www/bigbluebutton-default/assets/sietconnect/;
  add_header Cache-Control "no-cache";
}
NGINX
chmod 644 "$snippet"
if ! nginx -t; then
  if [[ -f $backup/route.before ]]; then cp "$backup/route.before" "$snippet"; else rm -f "$snippet"; fi
  echo "Asset route validation failed; previous route restored. Asset backups: $backup" >&2
  exit 1
fi
systemctl reload nginx
python3 "$source_dir/scripts/brand-bbb-client.py"
brand_script=/usr/local/libexec/sietconnect-brand-bbb-client.py
service_unit=/etc/systemd/system/sietconnect-playback-branding.service
timer_unit=/etc/systemd/system/sietconnect-playback-branding.timer
for unit in "$service_unit" "$timer_unit"; do
  if [[ -e $unit ]]; then
    grep -q '# Managed by SIETConnect assets' "$unit" || { echo "Unmanaged systemd unit exists: $unit" >&2; exit 1; }
    cp -a "$unit" "$backup/$(basename "$unit").before"
  fi
done
install -d -m 755 /usr/local/libexec
if [[ -e $brand_script ]]; then
  grep -q '# Managed by SIETConnect assets' "$brand_script" || { echo "Unmanaged branding script exists: $brand_script" >&2; exit 1; }
  cp -a "$brand_script" "$backup/$(basename "$brand_script").before"
fi
install -m 755 "$source_dir/scripts/brand-bbb-client.py" "$brand_script"
cat > "$service_unit" <<'UNIT'
# Managed by SIETConnect assets
[Unit]
Description=Apply SIETConnect branding to newly published BBB recordings

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/libexec/sietconnect-brand-bbb-client.py
UNIT
cat > "$timer_unit" <<'UNIT'
# Managed by SIETConnect assets
[Unit]
Description=Keep BBB recording playback branded as SIETConnect

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true
Unit=sietconnect-playback-branding.service

[Install]
WantedBy=timers.target
UNIT
chmod 644 "$service_unit" "$timer_unit"
systemctl daemon-reload
systemctl enable --now sietconnect-playback-branding.timer
printf 'College logo, browser icons, theme and playback branding timer installed. Backups: %s\n' "$backup"
