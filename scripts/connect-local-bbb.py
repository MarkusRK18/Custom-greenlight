#!/usr/bin/env python3
"""Connect the existing local portal only after authenticated BBB verification."""
from pathlib import Path
import shutil,subprocess,sys
project=Path(__file__).resolve().parent.parent
subprocess.run([sys.executable,str(project/'scripts/verify-local-bbb.py')],check=True)
secret=(project/'local-bbb/private/api-secret').read_text().strip()
envfile=project/'.env.local'
backup=project/'local-bbb/private/portal.env.before-bbb'
if not backup.exists():
 shutil.copyfile(envfile,backup)
 backup.chmod(0o600)
values={'BIGBLUEBUTTON_ENDPOINT':'https://bbb.srishakthi.test/bigbluebutton/api/','BIGBLUEBUTTON_SECRET':secret}
lines=[line for line in envfile.read_text().splitlines() if line.split('=',1)[0] not in values]
envfile.write_text('\n'.join(lines+[key+'='+value for key,value in values.items()])+'\n')
envfile.chmod(0o600)
print('Saved the local meeting-server credentials without displaying them.')
