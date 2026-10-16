#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
secret = Path('/local/private/api-secret').read_text().strip()
properties = {
    'securitySalt': secret,
    'disableRecordingDefault': 'false',
    'breakoutRoomsRecord': 'false',
    'autoStartRecording': 'true',
    'allowStartStopRecording': 'true',
    'defaultKeepEvents': 'true',
    'defaultWelcomeMessage': 'Welcome to SIETConnect',
    'beans.presentationService.defaultUploadedPresentation': '',
    'defaultWelcomeMessageFooter': '',
    'defaultCopyright': 'Sri Shakthi',
}
for filename in ['/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties', '/etc/bigbluebutton/bbb-web.properties']:
    path = Path(filename)
    lines = path.read_text().splitlines() if path.exists() else []
    lines = [line for line in lines if line.split('=', 1)[0].strip() not in properties]
    path.write_text('\n'.join(lines + [f'{key}={value}' for key, value in properties.items()]) + '\n')
PY
if [ ! -f /etc/bigbluebutton/bbb-html5.yml ]; then
  touch /etc/bigbluebutton/bbb-html5.yml
fi
yq e -i '.public.app.clientTitle = "SIETConnect" | .public.app.branding.displayBrandingArea = true | .public.app.copyright = "Sri Shakthi" | .public.layout.hidePresentationOnJoin = true | .public.layout.showSessionDetailsOnJoin = false' /etc/bigbluebutton/bbb-html5.yml
yq e -i '.public.whiteboard.toolbar.initialSelectedTool = "select" | del(.public.whiteboard.toolbar.presenterTools) | del(.public.whiteboard.toolbar.multiUserTools) | del(.public.whiteboard.lockToolbarTools)' /etc/bigbluebutton/bbb-html5.yml
install -m 644 /local/sri-shakthi-logo.png /var/www/bigbluebutton-default/assets/images/logo.png
if [[ -f /local/college-favicon.ico ]]; then
  install -m 644 /local/college-favicon.ico /var/www/bigbluebutton-default/assets/favicon.ico
fi
install -d -m 755 /var/www/bigbluebutton-default/assets/sietconnect
install -m 644 /local/sri-shakthi-logo.png /var/www/bigbluebutton-default/assets/sietconnect/logo.png
install -m 644 /local/college-favicon.ico /var/www/bigbluebutton-default/assets/sietconnect/favicon.ico
install -m 644 /local/sietconnect-theme.css /var/www/bigbluebutton-default/assets/sietconnect/theme.css
install -m 644 /local/recording-speakers.js /var/www/bigbluebutton-default/assets/sietconnect/recording-speakers.js
if [[ -f /local/brand-bbb-client.py ]]; then python3 /local/brand-bbb-client.py; fi
ruby /local/enable-bbb-video-recording.rb --apply-no-restart
cat > /etc/bigbluebutton/nginx/sietconnect-assets.nginx <<'NGINX'
# Managed by SIETConnect assets
location ^~ /sietconnect-assets/ {
  alias /var/www/bigbluebutton-default/assets/sietconnect/;
  add_header Cache-Control "no-cache";
}
NGINX
# This image's rc.local contains a LibreOffice Docker build; local testing
# omits document conversion, so it does not need the host Docker socket.
systemctl unmask bbb-rap-starter.service bbb-rap-resque-worker.service >/dev/null
systemctl enable bbb-rap-starter.service bbb-rap-resque-worker.service >/dev/null
cat > /etc/systemd/system/sietconnect-speakers.service <<'UNIT'
[Unit]
Description=Publish SIETConnect recording speaker timelines
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /local/publish-speaker-timeline.py
ExecStart=/usr/bin/python3 /local/brand-bbb-client.py
UNIT
cat > /etc/systemd/system/sietconnect-speakers.timer <<'UNIT'
[Unit]
Description=Update SIETConnect recording speaker timelines
[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=sietconnect-speakers.service
[Install]
WantedBy=timers.target
UNIT
systemctl enable sietconnect-speakers.timer >/dev/null
systemctl mask bbb-rap-caption-inbox.service >/dev/null
# A privileged development container must not start logins on host virtual terminals.
systemctl mask getty.service getty@.service autovt@.service serial-getty@.service console-getty.service container-getty@.service getty.target getty@tty1.service getty@tty2.service getty@tty3.service getty@tty4.service getty@tty5.service getty@tty6.service >/dev/null
exec /bin/systemd --system --unit=multi-user.target
