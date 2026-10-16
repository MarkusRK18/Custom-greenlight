#!/usr/bin/env python3
"""Configure an existing native BBB 3 server behind a public IPv4 NAT.

Defaults to inspection only. --apply backs up and writes media configuration,
opens ports only in an already-active UFW, then restarts BBB. Router forwarding
must be configured separately. DuckDNS updates are optional and prompt securely.
"""
import argparse
import getpass
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request


def media_settings(settings, public_ip, private_ip):
    settings = json.loads(json.dumps(settings))
    media = settings.setdefault('mediasoup', {}).setdefault('webrtc', {})
    listen = media.setdefault('listenIps', [{'ip': '0.0.0.0'}])
    if not isinstance(listen, list) or not all(isinstance(item, dict) for item in listen):
        raise ValueError('Unsupported mediasoup listenIps configuration.')
    ipv4 = [item for item in listen if ':' not in str(item.get('ip', ''))]
    if not ipv4:
        listen.append({'ip': '0.0.0.0', 'announcedIp': public_ip})
    for item in ipv4:
        item['announcedIp'] = public_ip
    freeswitch = settings.setdefault('freeswitch', {})
    freeswitch['ip'] = public_ip
    freeswitch.setdefault('sip_ip', private_ip)
    return settings


def update_xml(text, public_ip, profile=False):
    replacements = ({'ext-rtp-ip': '$${external_rtp_ip}', 'ext-sip-ip': '$${external_sip_ip}',
                     'local-network-acl': 'none'} if profile else
                    {'external_rtp_ip': public_ip, 'external_sip_ip': public_ip})
    for name, value in replacements.items():
        if profile:
            pattern = r'(<param\b[^>]*\bname=["\']' + re.escape(name) + r'["\'][^>]*\bvalue=["\'])[^"\']*(["\'])'
        else:
            pattern = r'(<X-PRE-PROCESS\b[^>]*\bdata=["\']' + re.escape(name) + r'=)[^"\']*(["\'])'
        # Ignore commented examples so they cannot be mistaken for active settings.
        chunks = re.split(r'(<!--.*?-->)', text, flags=re.S)
        count = 0
        for index in range(0, len(chunks), 2):
            chunks[index], matches = re.subn(pattern, lambda m: m[1] + value + m[2], chunks[index])
            count += matches
        if not count:
            raise ValueError(f'Missing native FreeSWITCH setting: {name}; refusing a partial configuration.')
        text = ''.join(chunks)
    return text


def local_hosts(text, hostname, private_ip):
    lines = []
    for line in text.splitlines():
        content, separator, comment = line.partition('#')
        fields = content.split()
        if len(fields) > 1 and hostname in fields[1:]:
            aliases = [alias for alias in fields[1:] if alias != hostname]
            if aliases:
                lines.append(fields[0] + ' ' + ' '.join(aliases) + (' #' + comment if separator else ''))
            elif separator:
                lines.append('#' + comment)
        else:
            lines.append(line)
    return '\n'.join(lines).rstrip() + f'\n{private_ip} {hostname} # SIETConnect server-local routing\n'


def yaml_read(path):
    command = ['ruby', '-ryaml', '-rjson', '-e',
               'v=YAML.safe_load(STDIN.read, permitted_classes: [Symbol], aliases: true)||{}; abort unless v.is_a?(Hash); puts JSON.generate(v)']
    result = subprocess.run(command, input=path.read_text() if path.exists() else '', text=True,
                            capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f'Invalid YAML in {path}; no configuration changed.')
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hostname', required=True)
    parser.add_argument('--public-ip', required=True)
    parser.add_argument('--private-ip', required=True)
    parser.add_argument('--portal-port', type=int, default=8445)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--update-duckdns', action='store_true')
    args = parser.parse_args()
    public = ipaddress.IPv4Address(args.public_ip)
    private = ipaddress.IPv4Address(args.private_ip)
    if not public.is_global or not private.is_private or private.is_loopback:
        parser.error('Use a public IPv4 address and the server LAN IPv4 address.')
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', args.hostname) or '..' in args.hostname:
        parser.error('Invalid hostname.')
    if not 1024 <= args.portal_port <= 65535:
        parser.error('Invalid portal port.')
    if os.geteuid() != 0:
        parser.error('Run with sudo on the native BBB server, including inspection mode.')
    for tool in ['ruby', 'bbb-conf', 'nginx']:
        if not shutil.which(tool):
            parser.error(f'Missing native BBB prerequisite: {tool}')
    subprocess.run(['nginx', '-t'], check=True)
    sfu = Path('/etc/bigbluebutton/bbb-webrtc-sfu/production.yml')
    variables = Path('/opt/freeswitch/conf/vars.xml')
    profile = Path('/opt/freeswitch/conf/sip_profiles/external.xml')
    hosts = Path('/etc/hosts')
    if not variables.is_file() or not profile.is_file():
        parser.error('Native FreeSWITCH files are missing; this script supports native BBB 3 installations.')
    # Refuse to accidentally rebrand or migrate an unrelated meeting server.
    properties = {}
    for path in [Path('/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties'), Path('/etc/bigbluebutton/bbb-web.properties')]:
        if path.is_file():
            for line in path.read_text().splitlines():
                if '=' in line and not line.lstrip().startswith('#'):
                    key, value = line.split('=', 1)
                    properties[key.strip()] = value.strip()
    configured = urllib.parse.urlparse(properties.get('bigbluebutton.web.serverURL', ''))
    if configured.scheme != 'https' or configured.hostname != args.hostname:
        parser.error('Hostname must match the existing HTTPS BBB serverURL. This script does not migrate hostnames or certificates.')
    native_client = Path('/etc/bigbluebutton/bbb-html5.yml')
    if native_client.exists():
        yaml_read(native_client)  # Do not restart BBB with a known invalid config.
    settings = media_settings(yaml_read(sfu), args.public_ip, args.private_ip)
    dumped = subprocess.run(['ruby', '-rjson', '-ryaml', '-e', 'puts YAML.dump(JSON.parse(STDIN.read))'],
                            input=json.dumps(settings), text=True, capture_output=True, check=True).stdout
    changes = {sfu: dumped, variables: update_xml(variables.read_text(), args.public_ip),
               profile: update_xml(profile.read_text(), args.public_ip, profile=True),
               hosts: local_hosts(hosts.read_text(), args.hostname, args.private_ip)}
    print(f'HTTPS meeting hostname: {args.hostname}; public IPv4: {public}; LAN server: {private}', flush=True)
    print(f'Router forwarding required: TCP 443 -> {private}:443; TCP {args.portal_port} -> {private}:{args.portal_port}; UDP 16384-32768 -> {private}:16384-32768.', flush=True)
    print('Keep TCP 80 reachable for HTTP-based certificate renewal if your certificate uses it. Do not forward public TCP 80 to port 8445 for ACME challenges.', flush=True)
    print('Server-local hostname routing uses the LAN IP to avoid requiring router hairpin NAT. Containers may also require split DNS or extra_hosts.', flush=True)
    print('Planned files: ' + ', '.join(map(str, changes)), flush=True)
    if not args.apply:
        print('Inspection only. Rerun with --apply between meetings; BBB will restart. --update-duckdns optionally prompts for its token.')
        return
    if args.update_duckdns:
        match = re.fullmatch(r'([a-z0-9-]+)\.duckdns\.org', args.hostname)
        if not match:
            parser.error('--update-duckdns requires a direct DuckDNS hostname.')
        token = getpass.getpass('DuckDNS token (hidden; not saved): ')
        if not token:
            parser.error('DuckDNS token is empty.')
        query = urllib.parse.urlencode({'domains': match[1], 'token': token, 'ip': args.public_ip})
        try:
            with urllib.request.urlopen('https://www.duckdns.org/update?' + query, timeout=20) as response:
                if response.read().strip() != b'OK':
                    raise ValueError()
        except Exception:
            raise SystemExit('DuckDNS update failed; token and request URL suppressed. No server configuration changed.') from None
        print('DuckDNS update accepted.', flush=True)
    backup = Path(tempfile.mkdtemp(prefix='sietconnect-public-bbb.', dir='/var/backups'))
    before = {path: path.read_bytes() if path.exists() else None for path in changes}
    for path in changes:
        if path.exists():
            destination = backup / path.relative_to('/')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
    try:
        for path, text in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            if before[path] is None:
                path.chmod(0o644)
        subprocess.run(['nginx', '-t'], check=True)
        subprocess.run(['bbb-conf', '--restart'], check=True)
    except Exception:
        for path, original in before.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original)
        subprocess.run(['bbb-conf', '--restart'], check=False)
        raise SystemExit(f'Server files restored after failure. Backup: {backup}. Any DuckDNS update remains applied.') from None
    if shutil.which('ufw'):
        status = subprocess.run(['ufw', 'status'], capture_output=True, text=True, check=True).stdout
        if re.search(r'^Status: active$', status, re.M):
            for port in ['443/tcp', f'{args.portal_port}/tcp', '16384:32768/udp']:
                subprocess.run(['ufw', 'allow', port], check=True)
        else:
            print('UFW is inactive; it was not enabled. Check any other firewall separately.')
    print(f'Native BBB media settings applied. Backups: {backup}', flush=True)
    print('Router forwarding and external HTTPS/audio/video connectivity are NOT verified. Test from mobile data.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
    except subprocess.CalledProcessError:
        raise SystemExit('A required native service/configuration command failed. Review its output before retrying.') from None
