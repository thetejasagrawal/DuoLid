#!/usr/bin/env python3
"""Static bundle/signature gate. Does not launch the app or draw on a display."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
release = len(sys.argv) > 2 and sys.argv[2] == "release"

def run(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT, text=True)

info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["LSMinimumSystemVersion"] == "14.0"
assert info["SURequireSignedFeed"] and info["SUVerifyUpdateBeforeExtraction"]
assert info["SUSignedFeedFailureExpirationInterval"] == 0
assert not info["SUEnableAutomaticChecks"] and not info["SUAutomaticallyUpdate"]
assert not info["SUAllowsAutomaticUpdates"]
assert not info["SUEnableSystemProfiling"] and not info["SUEnableJavaScript"]
binary = app / "Contents/MacOS/DuoLid"
assert set(run("lipo", "-archs", str(binary)).split()) == {"arm64", "x86_64"}
for architecture in ("arm64", "x86_64"):
    load = run("otool", "-arch", architecture, "-l", str(binary))
    assert "minos 14.0" in load
assert "@executable_path/../Frameworks" in run("otool", "-l", str(binary))
for path in ("Resources/DuoLid.icns", "Resources/Effects.metal", "Resources/LICENSE", "Resources/THIRD_PARTY_NOTICES.md", "Frameworks/Sparkle.framework/Sparkle"):
    assert (app / "Contents" / path).is_file(), path
framework = app / "Contents/Frameworks/Sparkle.framework"
assert (framework / "Versions/Current").is_symlink()
assert set(run("lipo", "-archs", str(framework / "Sparkle")).split()) == {"arm64", "x86_64"}
for item in [framework / "Versions/B/XPCServices/Downloader.xpc", framework / "Versions/B/XPCServices/Installer.xpc",
             framework / "Versions/B/Autoupdate", framework / "Versions/B/Updater.app", framework, app]:
    run("codesign", "--verify", "--strict", str(item))
    if release:
        signature = run("codesign", "-dvv", str(item))
        assert "TeamIdentifier=PPK4QC7R3L" in signature
        assert "runtime" in signature and "Timestamp=" in signature
if release:
    assert info["CFBundleIdentifier"] == "app.duolid.DuoLid"
    assert (app / "Contents/Resources/Effects.metallib").is_file()
else:
    assert info["CFBundleIdentifier"] == "app.duolid.DuoLid.Development"
print("Universal architectures, macOS 14 target, resources, updater policy, and nested signatures verified.")
