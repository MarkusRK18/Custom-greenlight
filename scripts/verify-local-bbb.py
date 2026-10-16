#!/usr/bin/env python3
"""Read-only BBB API verification using the private local test credentials."""
import hashlib,ssl,urllib.parse,urllib.request,xml.etree.ElementTree as ET
from pathlib import Path
project=Path(__file__).resolve().parent.parent
secret=(project/'local-bbb/private/api-secret').read_text().strip()
context=ssl.create_default_context(cafile=str(project/'local-bbb/certs/sri-shakthi-local-ca.crt'))
query=urllib.parse.urlencode({})
checksum=hashlib.sha1(('getMeetings'+query+secret).encode()).hexdigest()
url='https://bbb.srishakthi.test/bigbluebutton/api/getMeetings?checksum='+checksum
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context))
with opener.open(url, timeout=30) as response:
 root=ET.fromstring(response.read())
if root.findtext('returncode')!='SUCCESS':raise SystemExit('BBB API verification failed: '+str(root.findtext('messageKey')))
print('BigBlueButton authenticated API: SUCCESS')
print('Active meetings:',len(root.findall('./meetings/meeting')))
