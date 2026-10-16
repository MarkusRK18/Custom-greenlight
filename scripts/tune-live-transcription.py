#!/usr/bin/env python3
"""Remove only the verified BBB 3 caption-submit debounce, retaining backups."""
from pathlib import Path
import gzip
import re
import shutil


PATTERN = re.compile(
    r',(?P<pending>[A-Za-z_$][\w$]*)=[A-Za-z_$][\w$]*\((?P<submit>[A-Za-z_$][\w$]*),200\)'
    r'(?=,[A-Za-z_$][\w$]*=function\([^)]*\)\{(?P=submit)\([^{}]*,!0\)\})'
)


def tune(text):
    matches = [match for match in PATTERN.finditer(text)
               if 'transcriptId:' in text[max(0, match.start() - 800):match.start()]
               and 'isFinal:' in text[max(0, match.start() - 800):match.start()]
               and 'captions_speech_recognition_ended' in text[match.end():match.end() + 600]]
    if len(matches) != 1:
        return text
    match = matches[0]
    return text[:match.start()] + f",{match['pending']}={match['submit']}" + text[match.end():]


def main():
    count = 0
    for bundle in Path('/usr/share/bigbluebutton/html5-client').glob('bundle.*.js'):
        original = bundle.read_text()
        updated = tune(original)
        if updated == original:
            continue
        backup = bundle.with_name(bundle.name + '.before-sietconnect-captions')
        if not backup.exists():
            shutil.copy2(bundle, backup)
        bundle.write_text(updated)
        compressed = bundle.with_name(bundle.name + '.gz')
        if compressed.exists():
            shutil.copy2(compressed, compressed.with_name(compressed.name + '.before-sietconnect-captions'))
            compressed.write_bytes(gzip.compress(updated.encode()))
        brotli = bundle.with_name(bundle.name + '.br')
        if brotli.exists():
            shutil.copy2(brotli, brotli.with_name(brotli.name + '.before-sietconnect-captions'))
            brotli.unlink()
        count += 1
    print(f'Live transcription: removed caption-submit debounce from {count} matching client bundles; unmatched versions left unchanged.')


if __name__ == '__main__':
    main()
