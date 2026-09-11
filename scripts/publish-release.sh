#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 1 ] || { echo 'Usage: scripts/publish-release.sh dist/candidates/VERSION-BUILD' >&2; exit 64; }
candidate="$1"
python3 scripts/check-release-gates.py
python3 scripts/verify-candidate.py "$candidate"
test -z "$(git status --porcelain)" || { echo 'Commit all intended changes before publishing.' >&2; exit 1; }
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$candidate/provenance.json")"
commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$candidate/provenance.json")"
build="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$candidate/provenance.json")"
# Reject stale binaries if any shipped input changed after candidate creation.
test -z "$(git diff --name-only "$commit" HEAD -- Sources Resources Package.swift Package.resolved scripts LICENSE THIRD_PARTY_NOTICES.md)" || { echo 'Candidate is stale; rebuild with a higher build number.' >&2; exit 1; }
if gh release view "v$version" --repo thetejasagrawal/DuoLid >/dev/null 2>&1; then
    echo 'This version already exists. Published artifacts are immutable; use a higher version/build.' >&2; exit 1
fi
if [ -f updates/release.json ]; then
    python3 - "$build" <<'PY'
import json, sys
current = json.load(open('updates/release.json'))
assert int(sys.argv[1]) > int(current.get('build', 0)), 'Build number must increase monotonically'
PY
fi
git tag -a "v$version" -m "DuoLid $version" "$commit"
git push origin "v$version"
flags=(--verify-tag)
if [[ "$version" == *-beta* ]]; then flags+=(--prerelease); fi
gh release create "v$version" --repo thetejasagrawal/DuoLid --draft "${flags[@]}" \
    --title "DuoLid $version" --notes-file docs/release/notes.md \
    "$candidate/DuoLid-$version.dmg" "$candidate/DuoLid-$version.zip" "$candidate/SHA256SUMS" "$candidate/provenance.json" "$candidate/appcast.xml"
# Download the uploaded draft assets and compare before making them public.
verification="$(mktemp -d "$PWD/.build/upload-check.XXXXXX")"
trap 'rm -rf "$verification"' EXIT
gh release download "v$version" --repo thetejasagrawal/DuoLid --dir "$verification"
for asset in "DuoLid-$version.dmg" "DuoLid-$version.zip" SHA256SUMS provenance.json appcast.xml; do cmp "$candidate/$asset" "$verification/$asset"; done
gh release edit "v$version" --repo thetejasagrawal/DuoLid --draft=false
# Only now publish the exact signed feed and activate the README download button.
cp "$candidate/appcast.xml" updates/appcast.xml
python3 - "$version" "$build" <<'PY'
import json, pathlib, sys
version, build = sys.argv[1:]
pathlib.Path('updates/release.json').write_text(json.dumps({
    'status': 'available', 'version': version, 'build': int(build), 'beta': '-beta' in version,
    'download': f'https://github.com/thetejasagrawal/DuoLid/releases/download/v{version}/DuoLid-{version}.dmg',
    'notes': f'https://github.com/thetejasagrawal/DuoLid/releases/tag/v{version}'
}, indent=2) + '\n')
PY
python3 scripts/readme-release.py --write
python3 scripts/check-repository.py
git add updates/appcast.xml updates/release.json README.md
git commit -m "Publish DuoLid $version download and signed update feed"
git push origin main
