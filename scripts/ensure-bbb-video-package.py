#!/usr/bin/env python3
"""Install the optional BBB video format from the server's existing APT repository."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

BASE = Path('/usr/local/bigbluebutton/core/scripts')
PACKAGE = 'bbb-playback-video'


def missing_components():
    missing = [str(BASE / name) for name in ('process/video.rb', 'publish/video.rb', 'video.yml')
               if not (BASE / name).is_file()]
    if (BASE / 'video.yml').is_file():
        playback = subprocess.check_output(['ruby', '-ryaml', '-e',
                                            'puts YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [Symbol], aliases: true).fetch("playback_dir")',
                                            str(BASE / 'video.yml')], text=True).strip()
        template = Path(playback) / 'index.html.erb'
        if not template.is_file():
            missing.append(str(template))
    return missing


def series(version):
    match = re.match(r'(?:\d+:)?(\d+\.\d+)', version)
    return match[1] if match else None


def changes_to_existing_packages(plan):
    changes = []
    for line in plan.splitlines():
        if line.startswith('Remv '):
            changes.append(line.split()[1])
        match = re.match(r'^Inst (\S+) \[([^]]+)\] \((\S+)', line)
        if match and not (match[1] == PACKAGE and match[2] == match[3]):
            changes.append(match[1])
    return changes


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run this helper as root on the native BBB server.')
    if not missing_components():
        print('BBB combined-video components are already installed.')
        return
    for command in ('apt-get', 'apt-cache', 'dpkg-query'):
        if not shutil.which(command):
            raise SystemExit(f'Missing {command}. Install {PACKAGE} for this BBB release, then rerun the installer.')
    installed = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', 'bbb-playback-presentation'], text=True).strip()
    print(f'Installing missing {PACKAGE} for BBB recording release {installed}...', flush=True)
    subprocess.run(['apt-get', 'update'], check=True)
    environment = dict(os.environ, LC_ALL='C')
    policy = subprocess.check_output(['apt-cache', 'policy', PACKAGE], text=True, env=environment)
    match = re.search(r'^\s*Candidate:\s*(\S+)', policy, re.M)
    candidate = match[1] if match else '(none)'
    if not series(installed) or series(candidate) != series(installed):
        raise SystemExit(f'No matching {PACKAGE} candidate for BBB {series(installed) or installed}. '
                         'Check the existing BBB APT repository; no packages were installed.')
    command = ['apt-get', '--no-remove', '--no-install-recommends', '--reinstall', 'install', f'{PACKAGE}={candidate}']
    plan = subprocess.check_output([*command, '--simulate'], text=True, env=environment)
    changes = changes_to_existing_packages(plan)
    if changes:
        raise SystemExit('Video-format installation would change existing packages: ' + ', '.join(changes) +
                         '. Review the APT plan during maintenance before continuing; no packages were installed.')
    override = Path('/etc/bigbluebutton/recording/recording.yml')
    if override.is_file():
        Path('/var/backups').mkdir(parents=True, exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix='sietconnect-video-package.', dir='/var/backups'))
        backup.chmod(0o700)
        shutil.copy2(override, backup / 'recording.yml.before')
        print(f'Existing recording workflow backup: {backup}', flush=True)
    subprocess.run([*command, '--yes'], check=True, env=environment)
    missing = missing_components()
    if missing:
        raise SystemExit('The video package installed but components are still missing: ' + ', '.join(missing))
    print('BBB combined-video package and playback assets: OK')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'BBB video package setup failed ({error.cmd[0]} exited {error.returncode}). '
                         'Check the package-manager output and rerun the installer.') from None
