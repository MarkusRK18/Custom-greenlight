#!/usr/bin/env python3
"""Install only the local BBB hostname and test CA; run through pkexec."""
from pathlib import Path
import shutil
import subprocess
import os

if os.geteuid() != 0:
    raise SystemExit('Root authorization is required to configure /etc/hosts and CA trust.')
project = Path('/home/cys03/greenlight')
hosts = Path('/etc/hosts')
backup = project / 'local-bbb/private/hosts.before-bbb'
if not backup.exists():
    shutil.copyfile(hosts, backup)
    backup.chmod(0o600)
existing = hosts.read_text()
hostname = 'bbb.srishakthi.test'
entry = '172.30.50.10 bbb.srishakthi.test # Sri Shakthi local BBB testing\n'
lines = [line for line in existing.splitlines(keepends=True) if hostname not in line.split('#', 1)[0].split()[1:]]
updated = ''.join(lines)
if updated and not updated.endswith('\n'):
    updated += '\n'
hosts.write_text(updated + entry)
ca = project / 'local-bbb/certs/sri-shakthi-local-ca.crt'
subprocess.run(['/usr/bin/trust', 'anchor', '--store', str(ca)], check=True)
print('Configured bbb.srishakthi.test and trusted the local testing CA.')
