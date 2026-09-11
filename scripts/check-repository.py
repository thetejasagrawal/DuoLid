#!/usr/bin/env python3
"""Validate the README, its assets, and the GitHub-hosted update configuration."""
from html.parser import HTMLParser
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
readme = (root / 'README.md').read_text()


class MediaParser(HTMLParser):
    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if tag == 'img':
            assert all(attrs.get(key) for key in ('alt', 'width', 'height')), 'Images require alt text and dimensions'
        for key in ('src', 'href'):
            if attrs.get(key):
                check_link(attrs[key])


def check_link(link):
    parsed = urlsplit(link)
    if parsed.scheme:
        assert parsed.scheme == 'https', f'Non-HTTPS link: {link}'
    elif parsed.path:
        assert (root / unquote(parsed.path)).is_file(), f'Missing README target: {link}'


MediaParser().feed(readme)
for link in re.findall(r'\]\(([^\s)]+)\)', readme):
    check_link(link)
subprocess.run([sys.executable, 'scripts/readme-release.py'], cwd=root, check=True)
assert '/releases/latest' not in readme, 'Prereleases need an explicit versioned download'
assert 'github.io' not in readme, 'The README replaces the landing page'
metadata = json.loads((root / 'updates/release.json').read_text())
if metadata['status'] == 'available':
    assert (root / 'updates/appcast.xml').is_file(), 'Published builds need their signed feed'
feed_url = 'https://raw.githubusercontent.com/thetejasagrawal/DuoLid/main/updates/appcast.xml'
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
assert info['SUFeedURL'] == feed_url
assert feed_url in (root / 'Sources/DuoLidCore/UpdatePolicy.swift').read_text()
assert not (root / '.github/workflows/pages.yml').exists()
print('README assets, versioned downloads, and signed-feed configuration verified.')
