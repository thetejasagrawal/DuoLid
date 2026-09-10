#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-development}"
case "$mode" in development|debug) configuration=debug; release=false ;; release) configuration=release; release=true ;; *) echo 'Usage: scripts/build.sh [development|release]' >&2; exit 64 ;; esac
identity=-
if $release; then
    test -z "$(git status --porcelain)" || { echo 'Release builds require a clean committed tree.' >&2; exit 1; }
    identity='Developer ID Application: Tejas Agrawal (PPK4QC7R3L)'
    security find-identity -v -p codesigning | grep -Fq "\"$identity\"" || { echo 'Required DuoLid Developer ID identity is unavailable.' >&2; exit 1; }
fi
swift package --force-resolved-versions resolve
extra_flags=(-Xswiftc -warnings-as-errors)
if $release; then extra_flags+=(-Xswiftc -DDUOLID_PACKAGED -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/DuoLid"); fi
for architecture in arm64 x86_64; do
    swift build -c "$configuration" --triple "$architecture-apple-macosx14.0" --disable-automatic-resolution "${extra_flags[@]}"
 done
stage="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/DuoLid.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
lipo -create ".build/arm64-apple-macosx/$configuration/DuoLid" ".build/x86_64-apple-macosx/$configuration/DuoLid" -output "$app/Contents/MacOS/DuoLid"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/DuoLid.icns "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
framework='.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
# Keep source-build resources available without relying on a developer's path.
cp Sources/DuoLid/Resources/Effects.metal "$app/Contents/Resources/Effects.metal"
if $release; then
    xcrun --sdk macosx metal -c -target air64-apple-macos14.0 -std=macos-metal2.4 Sources/DuoLid/Resources/Effects.metal -o "$stage/Effects.air"
    xcrun --sdk macosx metallib "$stage/Effects.air" -o "$app/Contents/Resources/Effects.metallib"
else
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.duolid.DuoLid.Development' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName DuoLid Development' "$app/Contents/Info.plist"
fi
# The packaged binary must resolve Sparkle from the bundle on a clean Mac.
python3 - "$app/Contents/MacOS/DuoLid" <<'PYTHON'
import re, subprocess, sys
binary = sys.argv[1]
load = subprocess.check_output(['otool', '-l', binary], text=True)
for path in set(re.findall(r'cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset', load)):
    if path.startswith('/') and not path.startswith('/usr/lib'):
        subprocess.check_call(['install_name_tool', '-delete_rpath', path, binary])
PYTHON
install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/DuoLid"
args=(--force --sign "$identity")
if $release; then args+=(--options runtime --timestamp); fi
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign from the innermost executable outward; never rely on codesign --deep.
codesign "${args[@]}" "$sparkle/XPCServices/Downloader.xpc"
codesign "${args[@]}" "$sparkle/XPCServices/Installer.xpc"
codesign "${args[@]}" "$sparkle/Autoupdate"
codesign "${args[@]}" "$sparkle/Updater.app"
codesign "${args[@]}" "$app/Contents/Frameworks/Sparkle.framework"
codesign "${args[@]}" "$app"
python3 scripts/verify-bundle.py "$app" "$mode"
output="$PWD/dist/$mode"
mkdir -p "$output"
# Replace only this script's own build output, never an installed application.
if [ -d "$output/DuoLid.app" ]; then rm -rf "$output/DuoLid.app"; fi
ditto "$app" "$output/DuoLid.app"
python3 scripts/provenance.py "$output/DuoLid.app" "$output/provenance.json"
printf 'Built %s\n' "$output/DuoLid.app"
