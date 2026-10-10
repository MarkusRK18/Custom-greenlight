#!/usr/bin/env python3
"""Set an explicit college favicon in BBB's HTML entrypoint; retain a backup."""
from pathlib import Path
import gzip
import re
import shutil

page = Path('/usr/share/bigbluebutton/html5-client/index.html')
if page.exists():
    text = page.read_text()
    backup = page.with_name('index.html.before-sietconnect')
    if not backup.exists():
        shutil.copy2(page, backup)
    text = re.sub(r'<link\b[^>]*rel=["\'](?:shortcut )?icon["\'][^>]*>', '', text, flags=re.I)
    text = re.sub(r'<title>.*?</title>', '<title>SIETConnect</title>', text, flags=re.S)
    text = text.replace('</head>', '<link rel="icon" type="image/png" href="/sietconnect-assets/logo.png?v=2"></head>')
    page.write_text(text)
    compressed = page.with_name('index.html.gz')
    if compressed.exists():
        compressed.write_bytes(gzip.compress(text.encode()))
    # Avoid serving an obsolete precompressed entrypoint.
    brotli = page.with_name('index.html.br')
    if brotli.exists():
        brotli.rename(page.with_name('index.html.br.before-sietconnect'))
