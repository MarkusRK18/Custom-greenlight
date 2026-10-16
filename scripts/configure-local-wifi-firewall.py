#!/usr/bin/env python3
"""Permit SIETConnect LAN ports through active host UFW; preserve other rules."""
from pathlib import Path
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import tempfile

if os.geteuid() != 0:
    raise SystemExit('Administrator access is required to update UFW.')
ip = ipaddress.IPv4Address(sys.argv[1])
if not ip.is_private or ip.is_loopback or ip.is_link_local:
    raise SystemExit('Use a private LAN address.')
interfaces = json.loads(subprocess.check_output(['ip', '-j', '-4', 'address', 'show'], text=True))
matched = [(interface['ifname'], address) for interface in interfaces for address in interface.get('addr_info', [])
           if address.get('local') == str(ip) and address.get('scope') == 'global']
if len(matched) != 1:
    raise SystemExit('The LAN IP must be assigned to exactly one local interface.')
interface, address = matched[0]
subnet = str(ipaddress.IPv4Network(f'{ip}/{address["prefixlen"]}', strict=False))
routes = json.loads(subprocess.check_output(['ip', '-j', '-4', 'route', 'get', '172.30.50.10'], text=True))
bridge = routes[0]['dev']
if not bridge.startswith('br-'):
    raise SystemExit('The local BBB container must be on its dedicated Docker bridge.')
ufw = '/usr/bin/ufw'
status = subprocess.check_output([ufw, 'status'], text=True)
if not status.startswith('Status: active'):
    print('Host UFW is inactive; no firewall changes needed.')
    raise SystemExit(0)
Path('/var/backups').mkdir(parents=True, exist_ok=True)
backup = Path(tempfile.mkdtemp(prefix='sietconnect-wifi.', dir='/var/backups'))
backup.chmod(0o700)
for name in ('user.rules', 'user6.rules'):
    source = Path('/etc/ufw') / name
    if source.exists():
        shutil.copy2(source, backup / name)
rules = [
    ['allow', 'in', 'on', interface, 'from', subnet, 'to', str(ip), 'port', '443,8443,8080', 'proto', 'tcp'],
    ['allow', 'in', 'on', bridge, 'from', '172.30.50.0/24', 'to', str(ip), 'port', '443', 'proto', 'tcp'],
    ['route', 'allow', 'in', 'on', interface, 'out', 'on', bridge, 'from', subnet, 'to', '172.30.50.10',
     'port', '443,8443,8080', 'proto', 'tcp'],
]
for ports in ('16384:16447', '20000:20127'):
    rules.append(['route', 'allow', 'in', 'on', interface, 'out', 'on', bridge, 'from', subnet, 'to', '172.30.50.10',
                  'port', ports, 'proto', 'udp'])
for rule in rules:
    subprocess.run([ufw, *rule, 'comment', 'SIETConnect local Wi-Fi'], check=True)
print(f'SIETConnect LAN firewall rules installed for {subnet}. Backup: {backup}')
