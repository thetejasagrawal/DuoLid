#!/usr/bin/env python3
import base64
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / 'provenance.json').read_text())
assert not metadata['dirty'], 'Candidate was built from uncommitted input'
for line in (root / 'SHA256SUMS').read_text().splitlines():
    digest, filename = line.split('  ', 1)
    assert '/' not in filename and not filename.startswith('.'), 'Unsafe checksum path'
    assert hashlib.sha256((root / filename).read_bytes()).hexdigest() == digest, filename
feed_bytes = (root / 'appcast.xml').read_bytes()
signing_block = re.search(rb'<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?\Z', feed_bytes)
assert signing_block is not None, 'Feed has no valid trailing signature block'
assert int(signing_block[2]) == signing_block.start(), 'Signed feed byte count mismatch'
public_key = plistlib.loads(pathlib.Path('Resources/Info.plist').read_bytes())['SUPublicEDKey']
subprocess.run(['swift', 'scripts/verify-signature.swift', public_key, str(root / 'appcast.xml'),
                signing_block[1].decode(), signing_block[2].decode()], check=True)
feed = ET.fromstring(feed_bytes)
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = feed.findall('./channel/item')
current = [item for item in items if item.findtext(ns + 'version') == metadata['build']]
assert len(current) == 1
item = current[0]
assert item.findtext(ns + 'shortVersionString') == metadata['version']
assert item.findtext(ns + 'minimumSystemVersion') == '14.0'
if '-beta' in metadata['version']: assert item.findtext(ns + 'channel') == 'beta'
enclosure = item.find('enclosure')
expected = f"https://github.com/thetejasagrawal/DuoLid/releases/download/v{metadata['version']}/DuoLid-{metadata['version']}.zip"
assert enclosure is not None and enclosure.attrib['url'] == expected
assert len(base64.b64decode(enclosure.attrib[ns + 'edSignature'])) == 64
assert int(enclosure.attrib['length']) == (root / f"DuoLid-{metadata['version']}.zip").stat().st_size
subprocess.run(['swift', 'scripts/verify-signature.swift', public_key,
                str(root / f"DuoLid-{metadata['version']}.zip"), enclosure.attrib[ns + 'edSignature']], check=True)
for label in ('app', 'dmg'):
    assert json.loads((root / 'submissions' / f'{label}.json').read_text())['status'] == 'Accepted'
print('Candidate checksums, notarization outcomes, and public-key feed/archive signatures verified.')
