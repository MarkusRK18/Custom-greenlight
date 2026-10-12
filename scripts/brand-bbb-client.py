#!/usr/bin/env python3
"""Set an explicit college favicon in BBB's HTML entrypoint; retain a backup."""
from pathlib import Path
import gzip
import re
import shutil
import json

def save(path, text):
    backup = path.with_name(path.name + '.before-sietconnect')
    if not backup.exists():
        shutil.copy2(path, backup)
    path.write_text(text)
    compressed = path.with_name(path.name + '.gz')
    if compressed.exists():
        compressed.write_bytes(gzip.compress(text.encode()))
    brotli = path.with_name(path.name + '.br')
    if brotli.exists():
        backup_br = brotli.with_name(brotli.name + '.before-sietconnect')
        if not backup_br.exists():
            shutil.copy2(brotli, backup_br)
        brotli.unlink()

for page in [Path('/usr/share/bigbluebutton/html5-client/index.html'), Path('/var/bigbluebutton/learning-dashboard/index.html')]:
    if not page.exists():
        continue
    text = page.read_text()
    backup = page.with_name('index.html.before-sietconnect')
    if not backup.exists():
        shutil.copy2(page, backup)
    text = re.sub(r'<link\b[^>]*rel=["\'](?:shortcut )?icon["\'][^>]*>', '', text, flags=re.I)
    text = re.sub(r'<title>.*?</title>', '<title>SIETConnect</title>', text, flags=re.S)
    text = text.replace('</head>', '<link rel="icon" type="image/png" href="/sietconnect-assets/logo.png?v=3"></head>')
    save(page, text)

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
        branded = re.sub(r'^(\s*clientTitle:\s*).+$', r'\1SIETConnect', text, flags=re.M)
        if text != branded:
            save(settings, branded)

# The native dashboard bundles its tab title instead of using HTML5 locales.
for bundle in Path('/var/bigbluebutton/learning-dashboard/static/js').glob('*.js'):
    text = bundle.read_text()
    branded = re.sub(r'(["\'])BigBlueButton\1', r'\1SIETConnect\1', text)
    if text != branded:
        save(bundle, branded)
