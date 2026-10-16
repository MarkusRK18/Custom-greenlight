#!/usr/bin/env python3
# Managed by SIETConnect assets
"""Set an explicit college favicon in BBB's HTML entrypoint; retain a backup."""
from pathlib import Path
import gzip
import re
import shutil
import json
import subprocess

def save_bytes(path, data):
    backup = path.with_name(path.name + '.before-sietconnect')
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_bytes(data)
    compressed = path.with_name(path.name + '.gz')
    if compressed.exists():
        compressed.write_bytes(gzip.compress(data))
    brotli = path.with_name(path.name + '.br')
    if brotli.exists():
        backup_br = brotli.with_name(brotli.name + '.before-sietconnect')
        if not backup_br.exists():
            shutil.copy2(brotli, backup_br)
        brotli.unlink()

def save(path, text):
    save_bytes(path, text.encode())

pages = [Path('/usr/share/bigbluebutton/html5-client/index.html'), Path('/var/bigbluebutton/learning-dashboard/index.html')]
pages.extend(Path('/var/bigbluebutton/playback').glob('*/index.html'))
pages.extend(Path('/var/bigbluebutton/playback').glob('*/*/index.html'))
pages.extend(Path('/var/bigbluebutton/published/video').glob('*/index.html'))
for page in pages:
    if not page.exists():
        continue
    original = page.read_text()
    text = original
    backup = page.with_name('index.html.before-sietconnect')
    if not backup.exists():
        shutil.copy2(page, backup)
    text = re.sub(r'<link\b[^>]*rel=["\'](?:shortcut )?icon["\'][^>]*>', '', text, flags=re.I)
    text = re.sub(r'<title>.*?</title>', '<title>SIETConnect</title>', text, flags=re.S)
    text = text.replace('BigBlueButton recording playback', 'SIETConnect recording playback')
    text = re.sub(r'<link\b[^>]*data-sietconnect-theme=["\']true["\'][^>]*>', '', text, flags=re.I)
    text = re.sub(r'<script\b[^>]*data-sietconnect-speakers=["\']true["\'][^>]*></script>', '', text, flags=re.I)
    text = re.sub(r'<script\b[^>]*data-sietconnect-meeting-end=["\']true["\'][^>]*></script>', '', text, flags=re.I)
    if str(page) == '/usr/share/bigbluebutton/html5-client/index.html':
        text = text.replace('<head>', '<head><script data-sietconnect-meeting-end="true" src="/sietconnect-assets/meeting-ended-redirect.js?v=3"></script>', 1)
    text = text.replace('</head>', '<link rel="icon" type="image/x-icon" href="/sietconnect-assets/favicon.ico?v=7">'
                        '<link rel="stylesheet" data-sietconnect-theme="true" href="/sietconnect-assets/theme.css?v=10"></head>')
    if '/playback/' in str(page) or '/published/video/' in str(page):
        text = re.sub(r'<footer>Recorded with <a href="http://bigbluebutton.org">BigBlueButton</a>\.</footer>',
                      '<footer>SIETConnect</footer>', text)
        text = text.replace('</body>', '<script data-sietconnect-speakers="true" src="/sietconnect-assets/recording-speakers.js?v=3"></script></body>')
    if text != original:
        save(page, text)

# Replace only the packaged recording-player placeholder, never meeting content.
logo = Path('/var/www/bigbluebutton-default/assets/sietconnect/logo.png')
if logo.is_file():
    crest = logo.read_bytes()
    for placeholder in Path('/var/bigbluebutton/playback').glob('**/static/media/logo*.png'):
        if placeholder.read_bytes() != crest:
            save_bytes(placeholder, crest)

def brand_values(value):
    if isinstance(value, dict):
        return {key: brand_values(item) for key, item in value.items()}
    if isinstance(value, list):
        return [brand_values(item) for item in value]
    if isinstance(value, str):
        # Preserve technical URLs and translation keys.
        parts = re.split(r'(https?://[^\s<>"\']+)', value)
        for i in range(0, len(parts), 2):
            parts[i] = re.sub(r'\bBigBlueButton\b', 'SIETConnect', parts[i], flags=re.I)
        return ''.join(parts)
    return value

for locale in Path('/usr/share/bigbluebutton/html5-client/locales').glob('*.json'):
    original = json.loads(locale.read_text())
    branded = brand_values(original)
    if branded != original:
        save(locale, json.dumps(branded, ensure_ascii=False))

for settings in [Path('/usr/share/bigbluebutton/html5-client/private/config/settings.yml'), Path('/etc/bigbluebutton/bbb-html5.yml')]:
    if settings.exists():
        text = settings.read_text()
        validation = subprocess.run(
            ['ruby', '-ryaml', '-e',
             'begin; YAML.safe_load(STDIN.read, permitted_classes: [Symbol], aliases: true); rescue Psych::Exception; exit 1; end'],
            input=text, text=True, capture_output=True,
        )
        if validation.returncode:
            print(f'Skipping invalid YAML without modifying it: {settings}')
            continue
        branded = re.sub(r'^([ \t]*clientTitle:)[ \t]*[^\n]*$', r'\1 SIETConnect', text, flags=re.M)
        for key, value in {'skipMeetingEnded': 'true', 'displayBbbServerVersion': 'false',
                           'showHelpButton': 'false', 'copyright': "'Sri Shakthi'"}.items():
            branded = re.sub(r'^([ \t]*' + key + r':)[ \t]*[^\n]*$', lambda match: match[1] + ' ' + value, branded, flags=re.M)
        if text != branded:
            save(settings, branded)

# The native dashboard bundles its tab title instead of using HTML5 locales.
for bundle in Path('/var/bigbluebutton/learning-dashboard/static/js').glob('*.js'):
    text = bundle.read_text()
    branded = re.sub(r'(["\'])BigBlueButton\1', r'\1SIETConnect\1', text)
    if text != branded:
        save(bundle, branded)
