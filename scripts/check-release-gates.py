#!/usr/bin/env python3
import json
import pathlib
import plistlib
import subprocess
import sys

record = json.loads(pathlib.Path('docs/release/acceptance.json').read_text())
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
required = {
    'strictBuildsAndTests', 'pinkScreenIncidentResolved', 'syntheticPresentation60',
    'syntheticPresentation120WhereSupported', 'livePresentation60',
    'livePresentation120WhereSupported', 'visualQuality', 'openDesktopIdle',
    'recovery', 'nativeAccessibility', 'preferencesAndAudio', 'installationAndUpdates'
}
missing = sorted(name for name in required if record.get('checks', {}).get(name) is not True)
info = plistlib.loads(pathlib.Path('Resources/Info.plist').read_bytes())
if record.get('schemaVersion') != 1: missing.append('acceptance schema')
if record.get('version') != info['CFBundleShortVersionString'] or record.get('build') != info['CFBundleVersion']:
    missing.append('acceptance version/build mismatch')
if not record.get('evidence'): missing.append('acceptance evidence')
# Evidence may name the app/tooling commit followed by documentation-only commits.
# Validate that no shipped input changed since that tested revision.
tested = record.get('testedCommit')
if not tested:
    missing.append('testedCommit')
else:
    subprocess.run(['git', 'merge-base', '--is-ancestor', tested, commit], check=True)
    changed = subprocess.check_output(['git', 'diff', '--name-only', tested, commit, '--', 'Sources', 'Resources', 'Package.swift', 'Package.resolved', 'scripts'], text=True)
    if changed.strip(): missing.append('shipped inputs changed after acceptance')
if record.get('blockers'): missing.append('unresolved blockers')
if missing:
    print('Release withheld: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)
print('Recorded release acceptance gates passed.')
