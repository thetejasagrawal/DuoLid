#!/usr/bin/env python3
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys

app, destination = map(pathlib.Path, sys.argv[1:3])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
def output(*args):
    return subprocess.check_output(args, text=True).strip()

record = {
    "schemaVersion": 1,
    "commit": output("git", "rev-parse", "HEAD"),
    "sourceDateEpoch": int(output("git", "show", "-s", "--format=%ct", "HEAD")),
    "dirty": bool(output("git", "status", "--porcelain")),
    "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
    "bundleIdentifier": info["CFBundleIdentifier"],
    "swift": output("swift", "--version"), "xcode": output("xcodebuild", "-version"),
    "sdk": output("xcrun", "--sdk", "macosx", "--show-sdk-version"),
    "dependenciesSHA256": hashlib.sha256(pathlib.Path("Package.resolved").read_bytes()).hexdigest(),
    "architectures": output("lipo", "-archs", str(app / "Contents/MacOS/DuoLid")).split(),
    "note": "Build inputs are pinned; Apple signing timestamps and notarization tickets vary between builds."
}
destination.write_text(json.dumps(record, indent=2) + "\n")
