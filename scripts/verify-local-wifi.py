#!/usr/bin/env python3
"""Verify local Wi-Fi HTTPS, the public CA download and the authenticated BBB API."""
from pathlib import Path
import argparse
import hashlib
import ipaddress
import ssl
import time
import urllib.request
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('ip', help='Private IPv4 address of the host computer')
parser.add_argument('--timeout', type=int, default=240)
args = parser.parse_args()
ip = ipaddress.IPv4Address(args.ip)
if not ip.is_private or ip.is_loopback or not 1 <= args.timeout <= 600:
    parser.error('Use a private LAN IPv4 address and a timeout from 1 to 600 seconds.')
project = Path(__file__).resolve().parents[1]
ca = project / 'local-bbb/certs/sri-shakthi-local-ca.crt'
context = ssl.create_default_context(cafile=str(ca))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
secret = (project / 'local-bbb/private/api-secret').read_text().strip()
checksum = hashlib.sha1(('getMeetings' + secret).encode()).hexdigest()
deadline = time.monotonic() + args.timeout
next_report = time.monotonic() + 30
while True:
    phase = 'portal homepage'
    try:
        with opener.open(f'https://{ip}:8443/', timeout=5) as response:
            assert b'SIETConnect' in response.read()
        phase = 'portal health'
        with opener.open(f'https://{ip}:8443/health_check', timeout=5) as response:
            assert response.read().strip() == b'success'
        phase = 'authenticated BBB API'
        with opener.open(f'https://{ip}/bigbluebutton/api/getMeetings?checksum=' + checksum, timeout=5) as response:
            assert ET.fromstring(response.read()).findtext('returncode') == 'SUCCESS'
        phase = 'public CA download'
        with opener.open(f'http://{ip}:8080/local-ca.crt', timeout=5) as response:
            assert response.read() == ca.read_bytes()
        print('Wi-Fi HTTPS portal, authenticated BBB API and public CA download: OK', flush=True)
        break
    except Exception as error:
        if time.monotonic() >= deadline:
            raise SystemExit(f'Wi-Fi verification failed at {phase} ({type(error).__name__}). Check local service logs.')
        if time.monotonic() >= next_report:
            print(f'Waiting for {phase} ({type(error).__name__})...', flush=True)
            next_report = time.monotonic() + 30
        time.sleep(2)
