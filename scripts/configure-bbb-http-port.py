#!/usr/bin/env python3
"""Move native nginx HTTP listeners while preserving TLS and internal BBB ports."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def rewrite(text, port):
    return re.sub(
        r'(?m)^(\s*listen\s+)(?:(\[[^\]\n]+\]|[\w.*-]+):)?(?:80|8445)(?=\s|;)',
        lambda match: match[1] + (match[2] + ':' if match[2] else '') + str(port), text,
    )


def portal_config(port, upstream_port):
    return f'''# Managed by SIETConnect HTTP portal
server {{
    listen {port};
    listen [::]:{port};
    server_name ~^.+$;
    client_max_body_size 30m;
    location / {{
        proxy_pass http://127.0.0.1:{upstream_port};
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
    }}
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=80)
    parser.add_argument('--upstream-port', type=int, default=5050)
    args = parser.parse_args()
    if not 1 <= args.upstream_port <= 65535:
        parser.error('Invalid portal upstream port.')
    if args.port != 80 and not 1024 <= args.port <= 65535:
        parser.error('Use port 80 or a port between 1024 and 65535.')
    if os.geteuid() != 0:
        parser.error('Run with sudo on the nginx server.')
    subprocess.run(['nginx', '-t'], check=True)
    config = subprocess.run(['nginx', '-T'], capture_output=True, text=True, check=True).stdout
    paths = {Path(path).resolve() for path in re.findall(r'^# configuration file (.+):$', config, re.M)}
    changes = {}
    for path in paths:
        before = path.read_text()
        after = rewrite(before, args.port)
        if before != after:
            changes[path] = (before, after)
    portal = Path('/etc/nginx/sites-enabled/sietconnect-http-portal')
    before = portal.read_text() if portal.exists() else None
    if before is not None and not before.startswith('# Managed by SIETConnect HTTP portal'):
        parser.error('Refusing to overwrite unmanaged portal configuration.')
    after = portal_config(args.port, args.upstream_port)
    if before != after:
        changes[portal] = (before, after)
    if not changes:
        print('HTTP portal configuration is already up to date.')
        return
    backup = Path(tempfile.mkdtemp(prefix='sietconnect-http-port.', dir='/var/backups'))
    for path in changes:
        destination = backup / path.relative_to('/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            shutil.copy2(path, destination)
    try:
        for path, (_, updated) in changes.items():
            path.write_text(updated)
            path.chmod(0o644)
        subprocess.run(['nginx', '-t'], check=True)
        subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
    except Exception:
        for path, (original, _) in changes.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(original)
        subprocess.run(['nginx', '-t'], check=False)
        subprocess.run(['systemctl', 'reload', 'nginx'], check=False)
        raise
    print(f'HTTP listeners moved to {args.port}. HTTPS unchanged. Backups: {backup}')


if __name__ == '__main__':
    main()
