#!/usr/bin/env python3
"""Remove the native server advertisement from future meeting welcome messages."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def without_footer(text):
    text = re.sub(r'(?m)^[ \t]*defaultWelcomeMessageFooter[ \t]*[:=].*\n?', '', text)
    return text.rstrip('\n') + '\n' + 'defaultWelcomeMessageFooter=\n'


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo on the meeting server.')
    path = Path('/etc/bigbluebutton/bbb-web.properties')
    before = path.read_text()
    after = without_footer(before)
    if after == before:
        print('Meeting welcome footer is already disabled.')
        return
    backup = Path(tempfile.mkdtemp(prefix='sietconnect-welcome.', dir='/var/backups'))
    shutil.copy2(path, backup / path.name)
    try:
        path.write_text(after)
        subprocess.run(['systemctl', 'restart', 'bbb-web'], check=True)
    except Exception:
        path.write_text(before)
        subprocess.run(['systemctl', 'restart', 'bbb-web'], check=False)
        raise
    print(f'Server advertisement removed for new meetings. Backup: {backup}')


if __name__ == '__main__':
    main()
