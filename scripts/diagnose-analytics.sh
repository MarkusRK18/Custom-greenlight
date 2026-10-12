#!/usr/bin/env bash
# Read-only except for a harmless callback probe that cannot create a session.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo on your BBB server.' >&2; exit 1; }
install_dir=${1:-/opt/sietconnect}
echo 'SIETConnect analytics diagnostics (no credentials or participant data printed)'
for service in bbb-web.service bbb-rap-starter.service bbb-rap-resque-worker.service; do
  printf '%s: ' "$service"
  systemctl is-active "$service" || true
done
python3 - "$install_dir/installer.env" <<'PY'
from pathlib import Path
import json, sys, urllib.request, urllib.error, urllib.parse, ssl
from collections import deque
import xml.etree.ElementTree as ET
properties = {}
for file in ['/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties', '/etc/bigbluebutton/bbb-web.properties']:
 if Path(file).exists():
  for line in Path(file).read_text().splitlines():
   if '=' in line and not line.lstrip().startswith('#'):
    k,v=line.split('=',1); properties[k.strip()]=v.strip()
for key in ['disableRecordingDefault','defaultKeepEvents']:
 print(key+': '+properties.get(key,'not explicitly set'))
env = {}
if Path(sys.argv[1]).exists():
 for line in Path(sys.argv[1]).read_text().splitlines():
  if '=' in line:
   key,value=line.split('=',1); env[key]=value
public = env.get('SIET_PUBLIC_URL')
if public:
 url=public.rstrip('/')+'/analytics_callback'
 print('Configured callback: '+url)
 request=urllib.request.Request(url, data=json.dumps({'meeting_id':'__siet_diagnostic_missing_room__'}).encode(),headers={'Content-Type':'application/json'},method='POST')
 try:
  with urllib.request.urlopen(request,timeout=15) as response:
   print('Callback probe HTTP: '+str(response.status)+' (expected empty 404)')
 except urllib.error.HTTPError as error:
  print('Callback probe HTTP: '+str(error.code))
  print('Expected portal response: '+str(error.code==404 and len(error.read())==0))
 except (urllib.error.URLError, TimeoutError, ssl.SSLError):
  print('Callback probe FAILED: check server DNS, HTTPS trust and access to its own public hostname.')
else:
 print('Installer configuration not found; pass your installer directory as the first argument.')
for folder,pattern,label in [('/var/bigbluebutton/events','*/events.xml','Retained event files'),('/var/bigbluebutton/recording/raw','*/metadata.xml','Archived sessions')]:
 print(label+': '+str(len(list(Path(folder).glob(pattern)))))
events=sorted(Path('/var/bigbluebutton/events').glob('*/events.xml'),key=lambda p:p.stat().st_mtime,reverse=True)[:5]
configured=0
for event in events:
 try:
  with event.open('rb') as stream:
   for _,element in ET.iterparse(stream,events=['end']):
    if element.tag=='metadata':
     configured+=int(bool(element.attrib.get('analytics-callback-url')))
     break
 except (ET.ParseError,OSError):
  pass
print('Recent retained sessions with analytics callback configured: '+str(configured)+'/'+str(len(events)))
log=Path('/var/log/bigbluebutton/post_events_analytics_callback.log')
if log.exists():
 with log.open(errors='replace') as stream:
  lines=list(deque(stream,maxlen=200))
 for label,word in [('Successful callbacks','INFO -- : Success'),('Failed callbacks','Failed when calling'),('Callback exceptions','Rescued')]:
  print(label+' (last 200 log lines): '+str(sum(word in line for line in lines)))
else:
 print('No analytics callback processing log yet; check event retention and workers.')
print('Portal history check: use the deployment Compose commands in deploy/INSTALL.md to inspect portal logs and verify the analytics migration.')
PY
