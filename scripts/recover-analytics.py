#!/usr/bin/env python3
"""Replay retained ended-session analytics through the native BBB processor.

Run on the native meeting server with sudo after fixing callback routing.
"""
import argparse
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from urllib.parse import urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('public_url', help='Public HTTPS portal URL')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo on the meeting server.')
    public_url = args.public_url.rstrip('/')
    parsed = urlparse(public_url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.query or parsed.fragment or parsed.username or parsed.password:
        parser.error('Use the public HTTPS portal URL without credentials, query or fragment.')
    script_dir = Path('/usr/local/bigbluebutton/core/scripts')
    processor = script_dir / 'post_events/post_events_analytics_callback.rb'
    if not processor.is_file():
        raise SystemExit('Native analytics processor is missing.')
    attempted = 0
    for event_file in sorted(Path('/var/bigbluebutton/events').glob('*/events.xml')):
        try:
            root = ET.parse(event_file).getroot()
        except (OSError, ET.ParseError):
            continue
        metadata = root.find('metadata')
        if metadata is None or metadata.get('analytics-callback-url') != public_url + '/analytics_callback':
            continue
        if not any(event.get('eventname') == 'EndAndKickAllEvent' for event in root.iter('event')):
            continue
        subprocess.run(['ruby', str(processor), '-m', event_file.parent.name], cwd=script_dir,
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        attempted += 1
    print(f'Replay requested for {attempted} retained ended sessions. Run diagnose-analytics.sh to verify saved sessions.')


if __name__ == '__main__':
    main()
