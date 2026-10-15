#!/usr/bin/env python3
"""Separate portal startup failures from public HTTPS and nginx routing failures."""
import argparse
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


def probe(url, headers=None, timeout=10):
    try:
        with urlopen(Request(url, headers=headers or {}), timeout=timeout) as response:
            status, body = response.status, response.read(4096).strip()
    except HTTPError as error:
        status, body = error.code, error.read(4096).strip()
    except (URLError, TimeoutError, OSError):
        return False, 'connection, DNS or TLS failure'
    if status == 200 and body == b'success':
        return True, 'healthy'
    for phrase, component in [('Database', 'database'), ('Redis', 'Redis'), ('SMTP Server', 'SMTP'),
                              ('BigBlueButton', 'meeting API')]:
        if f'Unable to connect to {phrase}'.encode() in body:
            return False, f'HTTP {status}: {component} health check failed'
    return False, f'HTTP {status}: unexpected health response'


def wait_for(url, headers=None, deadline_seconds=120):
    deadline = time.monotonic() + deadline_seconds
    detail = 'not checked'
    while time.monotonic() < deadline:
        healthy, detail = probe(url, headers, timeout=max(0.1, min(10, deadline - time.monotonic())))
        if healthy:
            return True, detail
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    return False, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--public-url', required=True)
    args = parser.parse_args()
    public = urlparse(args.public_url)
    if not 1 <= args.port <= 65535 or public.scheme != 'https' or not public.hostname or public.username or public.password or public.query or public.fragment:
        parser.error('A valid published port and public HTTPS URL are required.')
    local_url = f"http://127.0.0.1:{args.port}{public.path.rstrip('/')}/health_check"
    healthy, detail = wait_for(local_url, {'Host': public.netloc, 'X-Forwarded-Proto': 'https'})
    if not healthy:
        raise SystemExit(f'Local portal is not ready: {detail}. Check the application, database, Redis and mail service.')
    print('Local portal health: OK', flush=True)
    healthy, detail = wait_for(args.public_url.rstrip('/') + '/health_check', deadline_seconds=30)
    if not healthy:
        raise SystemExit(f'Local portal is healthy, but public HTTPS failed: {detail}. Check nginx, DNS and certificate trust.')
    print('Public portal health: OK', flush=True)


if __name__ == '__main__':
    main()
