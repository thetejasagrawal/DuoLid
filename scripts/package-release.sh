#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Produces a notarized candidate. Publishing is a separate, gated operation.
profile='DuoLid-notary'
identity='Developer ID Application: Tejas Agrawal (PPK4QC7R3L)'
xcrun notarytool history --keychain-profile "$profile" --output-format json > /dev/null
bash scripts/build.sh release
app="$PWD/dist/release/DuoLid.app"
version="$(/usr/libexec/PlistBuddy -c Print:CFBundleShortVersionString "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c Print:CFBundleVersion "$app/Contents/Info.plist")"
output="$PWD/dist/candidates/$version-$build"
[ ! -e "$output" ] || { echo 'Candidate directory already exists. Preserve it; use a higher build number for a new candidate.' >&2; exit 1; }
mkdir -p "$output/submissions" "$output/feed"
cp dist/release/provenance.json "$output/provenance.json"
ditto dist/release/Symbols "$output/Symbols"
notarize() {
    local artifact="$1" label="$2"
    xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait --timeout 30m --output-format json > "$output/submissions/$label.json"
    python3 - "$output/submissions/$label.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Review the local submission result before continuing.')
PY
    local submission_id
    submission_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$output/submissions/$label.json")"
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$output/submissions/$label-log.json"
}
# Apple accepts ZIP as the app submission container. Staple the original app
# after acceptance, then make the distribution ZIP from that stapled app.
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/app-submission.zip"
notarize "$output/app-submission.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
work="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/DuoLid.app"
ln -s /Applications "$work/Applications"
printf 'Drag DuoLid to Applications. Requires macOS 14 or newer.\nAutomatic effects require a compatible lid-angle sensor.\n' > "$work/Install.txt"
dmg="DuoLid-$version.dmg"
archive="DuoLid-$version.zip"
hdiutil create -volname DuoLid -srcfolder "$work" -ov -format UDZO "$output/$dmg"
codesign --force --timestamp --sign "$identity" "$output/$dmg"
notarize "$output/$dmg" dmg
xcrun stapler staple "$output/$dmg"
xcrun stapler validate "$output/$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$output/$dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
cp "$output/$archive" "$output/feed/"
if [ -f site/appcast.xml ]; then cp site/appcast.xml "$output/feed/appcast.xml"; fi
cp docs/release/notes.md "$output/feed/DuoLid-$version.md"
tool_dir="$(bash scripts/fetch-sparkle.sh)"
channel=(--maximum-deltas 0)
if [[ "$version" == *-beta* ]]; then channel+=(--channel beta); fi
"$tool_dir/bin/generate_appcast" --account app.duolid.DuoLid --versions "$build" \
    --maximum-versions 0 --embed-release-notes "${channel[@]}" \
    --download-url-prefix "https://github.com/thetejasagrawal/DuoLid/releases/download/v$version/" \
    --link 'https://thetejasagrawal.github.io/DuoLid/' "$output/feed"
cp "$output/feed/appcast.xml" "$output/appcast.xml"
(cd "$output" && shasum -a 256 "$dmg" "$archive" appcast.xml provenance.json > SHA256SUMS)
python3 scripts/verify-candidate.py "$output"
printf 'Candidate ready for installation and update acceptance: %s\n' "$output"
