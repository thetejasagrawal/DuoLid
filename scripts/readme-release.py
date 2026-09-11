#!/usr/bin/env python3
"""Keep the README download block tied to the verified release metadata."""
import argparse
import json
from pathlib import Path
import re

REPOSITORY = 'https://github.com/thetejasagrawal/DuoLid'
BEGIN = '<!-- DUOLID-DOWNLOAD:START -->'
END = '<!-- DUOLID-DOWNLOAD:END -->'


def release_block(metadata):
    version = metadata.get('version', '')
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-zA-Z0-9]+(?:[.-][a-zA-Z0-9]+)*)?', version):
        raise ValueError('Invalid release version')
    if metadata.get('status') == 'available':
        expected = f'{REPOSITORY}/releases/download/v{version}/DuoLid-{version}.dmg'
        notes = f'{REPOSITORY}/releases/tag/v{version}'
        if metadata.get('download') != expected or metadata.get('notes') != notes:
            raise ValueError('Downloads must point to the exact versioned GitHub asset')
        if type(metadata.get('build')) is not int or metadata['build'] <= 0:
            raise ValueError('A published build must have a positive build number')
        if metadata.get('beta') is not ('-beta' in version):
            raise ValueError('Beta label does not match the version')
        label = 'Beta · ' if metadata['beta'] else ''
        body = f'''<p align="center">
  <a href="{expected}"><img src="docs/assets/download.svg" width="248" height="52" alt="Download DuoLid {version} for macOS"></a>
</p>
<p align="center"><sub>{label}{version} · macOS 14+ · Apple silicon &amp; Intel · <a href="{notes}">Release notes</a></sub></p>'''
    elif metadata.get('status') == 'preparing':
        if metadata.get('download') is not None:
            raise ValueError('An unpublished release cannot advertise a download')
        body = f'''<p align="center">
  <img src="docs/assets/download-soon.svg" width="248" height="52" alt="DuoLid beta download is not available yet">
</p>
<p align="center"><sub>{version} is in preparation. <a href="#availability">Release status</a> · <a href="{REPOSITORY}/releases">All releases</a></sub></p>'''
    else:
        raise ValueError('Unknown release status')
    return f'{BEGIN}\n{body}\n{END}'


def replace_block(readme, metadata):
    if readme.count(BEGIN) != 1 or readme.count(END) != 1:
        raise ValueError('The README must contain one download block')
    start, end = readme.index(BEGIN), readme.index(END)
    if start >= end:
        raise ValueError('Download markers are out of order')
    return readme[:start] + release_block(metadata) + readme[end + len(END):]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='Update the README from release metadata')
    args = parser.parse_args()
    path = Path('README.md')
    original = path.read_text()
    result = replace_block(original, json.loads(Path('updates/release.json').read_text()))
    if args.write:
        path.write_text(result)
    elif original != result:
        raise SystemExit('README download metadata is stale; run scripts/readme-release.py --write')
    print('README download state matches release metadata.')
