#!/usr/bin/env python3
"""Offline site/release-link gate; no browser or third-party dependencies."""
from html.parser import HTMLParser
import json
import pathlib
import urllib.parse

root = pathlib.Path('site')
class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids = set(); self.links = []; self.images = []
    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs['id'])
        for key in ('src', 'href', 'poster'):
            if key in attrs: self.links.append(attrs[key])
        if tag == 'img':
            assert 'alt' in attrs and 'width' in attrs and 'height' in attrs, attrs

parser = SiteParser(); parser.feed((root / 'index.html').read_text())
for link in parser.links:
    parsed = urllib.parse.urlsplit(link)
    if parsed.scheme:
        assert parsed.scheme == 'https', link
        continue
    if parsed.fragment and not parsed.path:
        assert parsed.fragment in parser.ids, link
    if parsed.path and parsed.path != './':
        assert (root / parsed.path).is_file(), f'Missing site asset: {link}'
release = json.loads((root / 'release.json').read_text())
assert release['status'] in ('preparing', 'available')
if release['status'] == 'available':
    assert release['download'] == f"https://github.com/thetejasagrawal/DuoLid/releases/download/v{release['version']}/DuoLid-{release['version']}.dmg"
    assert (root / 'appcast.xml').is_file(), 'Released site needs a signed appcast'
else:
    assert release['download'] is None
assert '/releases/latest' not in (root / 'index.html').read_text()
print('Static assets, accessible image metadata, internal links, and versioned download state verified.')
