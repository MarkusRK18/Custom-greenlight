#!/usr/bin/env python3
"""Apply optional LAN networking inside the local BBB development container."""
from pathlib import Path
import ipaddress
import re
import subprocess
import sys
import os

address = ipaddress.IPv4Address(sys.argv[1])
if not address.is_private or address.is_loopback or address.is_unspecified or address.is_link_local:
    raise SystemExit('Use a private LAN IPv4 address.')
ip = str(address)
subnet = ipaddress.IPv4Network(os.environ['LOCAL_BBB_LAN_SUBNET'])
if address not in subnet or not subnet.is_private:
    raise SystemExit('The LAN subnet must contain the selected private IP.')

# UFW needs its boot service and runtime files before its CLI can add rules.
# Install a oneshot instead of invoking the firewall before systemd starts.
commands = '\n'.join(f'ExecStart=/usr/sbin/ufw allow from {source} to any port 8080,8443 proto tcp comment SIETConnect-local-WiFi'
                     for source in (str(subnet), '172.30.50.0/24'))
Path('/etc/systemd/system/sietconnect-lan-firewall.service').write_text(f'''# Managed by SIETConnect local Wi-Fi setup
[Unit]
Description=Allow SIETConnect Wi-Fi ports in the local BBB container
Requires=ufw.service
After=ufw.service
Before=nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
{commands}

[Install]
WantedBy=multi-user.target
''')
subprocess.run(['systemctl', 'enable', 'sietconnect-lan-firewall.service'], check=True)

# The image boot script updates all BBB URLs with bbb-conf. Preserve the Docker
# hostname for internal DNS/cert mount paths, but advertise the LAN address.
rc = Path('/etc/rc.local')
text = rc.read_text()
text, count = re.subn(r'^THIS_HOST=.*$', f'THIS_HOST={ip}', text, flags=re.M)
if count != 1:
    raise SystemExit('Unrecognized BBB development image boot script.')
rc.write_text(text)

config = '/etc/bigbluebutton/bbb-webrtc-sfu/production.yml'
subprocess.run(['yq', 'e', '-i',
                '.mediasoup.webrtc.listenIps = [{"ip": "0.0.0.0", "announcedIp": "' + ip + '"}] | '
                '.mediasoup.webrtc.enableUdp = true | .mediasoup.webrtc.enableTcp = false | '
                '.mediasoup.worker.rtcMinPort = 20000 | .mediasoup.worker.rtcMaxPort = 20127', config], check=True)

variables = Path('/opt/freeswitch/conf/vars.xml')
text = variables.read_text()
for key in ('external_rtp_ip', 'external_sip_ip'):
    text, count = re.subn(r'(data="' + key + r'=)[^"]*', lambda match: match[1] + ip, text)
    if count == 0:
        raise SystemExit(f'FreeSWITCH {key} is missing.')
variables.write_text(text)
switch = Path('/opt/freeswitch/conf/autoload_configs/switch.conf.xml')
text = switch.read_text()
for name, value in (('rtp-start-port', '16384'), ('rtp-end-port', '16447')):
    text, count = re.subn(r'(<param\s+name="' + name + r'"\s+value=")[^"]*', lambda match: match[1] + value, text)
    if count != 1:
        raise SystemExit(f'FreeSWITCH {name} configuration is missing or ambiguous.')
switch.write_text(text)
external = Path('/opt/freeswitch/conf/sip_profiles/external.xml')
text = external.read_text()
for name, value in (('ext-rtp-ip', '$${external_rtp_ip}'), ('ext-sip-ip', '$${external_sip_ip}'), ('local-network-acl', 'none')):
    text = re.sub(r'(<param\s+name="' + name + r'"\s+value=")[^"]*', lambda match: match[1] + value, text)
external.write_text(text)

# Serve the existing portal with TLS on a separate port. Docker DNS resolves the
# portal on demand so restarting it does not leave nginx with a stale address.
Path('/etc/nginx/conf.d/sietconnect-lan.conf').write_text('''# Managed by SIETConnect local Wi-Fi setup
server {
    listen 8443 ssl;
    server_name _;
    ssl_certificate /local/certs/fullchain.pem;
    ssl_certificate_key /local/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 30m;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set $portal_upstream portal:3000;
        proxy_pass http://$portal_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
    }
}
server {
    listen 8080;
    server_name _;
    root /var/www/sietconnect-lan;
    location = / { try_files /index.html =404; }
    location = /local-ca.crt {
        alias /var/www/sietconnect-lan/local-ca.crt;
        default_type application/x-x509-ca-cert;
        add_header Content-Disposition 'attachment; filename="SIETConnect-Local-CA.crt"';
    }
    location / { return 404; }
}
''')
fingerprint = subprocess.check_output(['openssl', 'x509', '-in', '/local/certs/sri-shakthi-local-ca.crt',
                                      '-noout', '-sha256', '-fingerprint'], text=True).strip()
web = Path('/var/www/sietconnect-lan')
web.mkdir(parents=True, exist_ok=True)
web.chmod(0o755)
(web / 'local-ca.crt').write_bytes(Path('/local/certs/sri-shakthi-local-ca.crt').read_bytes())
(web / 'local-ca.crt').chmod(0o644)
(web / 'index.html').write_text(f'''<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SIETConnect Wi-Fi setup</title><style>body{{max-width:650px;margin:50px auto;padding:20px;font:17px/1.6 system-ui;color:#17351c}}a{{color:#004d00}}code{{overflow-wrap:anywhere}}</style></head>
<body><h1>SIETConnect on Wi-Fi</h1><p>Connect this device to the same Wi-Fi as the host computer.</p>
<ol><li><a href="/local-ca.crt">Download the local test CA certificate</a>.</li>
<li>On Android: Settings → Security → Encryption &amp; credentials → Install a certificate → CA certificate.
Select the downloaded SIETConnect certificate. Setting names vary by phone.</li>
<li>On a laptop: import the certificate into the trusted certificate authorities used by your browser.</li>
<li>Open <a href="https://{ip}:8443">SIETConnect</a>. Allow microphone and camera access when joining.</li></ol>
<p>Install this certificate only for this local test setup. Compare its fingerprint with the host computer:</p>
<p><code>{fingerprint}</code></p></body></html>''')
subprocess.run(['nginx', '-t'], check=True)
print(f'Configured local Wi-Fi portal: https://{ip}:8443')
