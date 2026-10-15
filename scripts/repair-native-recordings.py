#!/usr/bin/env python3
"""Deploy the recording fixes to one existing native meeting portal."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
from urllib.parse import urlparse


def discover(containers, selected=None, public_url=None):
    candidates = []
    for container in containers:
        config = container.get('Config', {})
        env = dict(item.split('=', 1) for item in config.get('Env', []) if '=' in item)
        image = config.get('Image', '').lower()
        name = container.get('Name', '').lstrip('/')
        matches = selected in [name, container.get('Id')] if selected else (
            ('greenlight' in image or 'sietconnect' in image) and 'DATABASE_URL' in env)
        if matches:
            candidates.append((container, env))
    if len(candidates) != 1:
        raise ValueError('Cannot identify one portal. Supply --container with its exact running container name.')
    app, env = candidates[0]
    labels = app.get('Config', {}).get('Labels') or {}
    project = labels.get('com.docker.compose.project')
    directory = labels.get('com.docker.compose.project.working_dir')
    service = labels.get('com.docker.compose.service')
    if not project or not directory or not service:
        raise ValueError('Selected portal has no Compose deployment labels; select deployment manually.')
    public = (public_url or env.get('BBB_CALLBACK_BASE_URL') or env.get('URL_HOST') or '').rstrip('/')
    parsed = urlparse(public)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('Cannot identify the public portal HTTPS URL. Supply --public-url.')
    services = {'app': service}
    for kind in ['postgres', 'redis']:
        found = set()
        for container in containers:
            config = container.get('Config', {})
            sibling_labels = config.get('Labels') or {}
            image = config.get('Image', '').split('/')[-1]
            if sibling_labels.get('com.docker.compose.project') == project and image.split(':')[0] == kind:
                found.add(sibling_labels.get('com.docker.compose.service'))
        if len(found) != 1 or None in found:
            raise ValueError(f'Cannot identify one {kind} service; use the installer manually.')
        services[kind] = found.pop()
    return directory, public, services


def install_arguments(source, directory, public, services):
    directory = Path(directory)
    command = ['bash', str(source / 'scripts/install-custom-greenlight.sh'), '--public-url', public]
    fresh_file = directory / 'compose.yml'
    try:
        fresh = json.loads(fresh_file.read_text()).get('name') == 'sietconnect'
    except (OSError, ValueError):
        fresh = False
    if fresh:
        if directory.name != 'portal' or services != {'app': 'greenlight-v3', 'postgres': 'postgres', 'redis': 'redis'}:
            raise ValueError('Managed deployment does not match installer layout; use installer manually.')
        command += ['--fresh', '--install-dir', str(directory.parent)]
    else:
        command += ['--greenlight-dir', str(directory), '--app-service', services['app'],
                    '--postgres-service', services['postgres'], '--redis-service', services['redis']]
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container')
    parser.add_argument('--public-url')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo on the meeting server.')
    source = Path(__file__).resolve().parents[1]
    try:
        ids = subprocess.run(['docker', 'ps', '-q'], capture_output=True, text=True, check=True).stdout.split()
        if not ids:
            raise ValueError('No running containers found.')
        result = subprocess.run(['docker', 'inspect', *ids], capture_output=True, text=True, check=True)
        directory, public, services = discover(json.loads(result.stdout), args.container, args.public_url)
        command = install_arguments(source, directory, public, services)
        print(f'Existing portal: {directory}; application service: {services["app"]}; public URL: {public}', flush=True)
        if args.dry_run:
            print(shlex.join(command))
            return
        subprocess.run(command, check=True)
        print('Deployment completed. Start a new meeting to test automatic recording.')
    except subprocess.CalledProcessError:
        raise SystemExit('Repair command failed. Docker inspection details were suppressed to protect credentials.')
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
