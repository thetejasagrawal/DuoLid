#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tool_dir="$PWD/.build/release-tools/Sparkle-2.9.6"
if [ ! -x "$tool_dir/bin/generate_appcast" ]; then
    mkdir -p "$tool_dir"
    archive="$tool_dir/Sparkle-2.9.6.tar.xz"
    curl --fail --location --proto '=https' --tlsv1.2 \
        https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz -o "$archive"
    expected=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
    actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
    [ "$actual" = "$expected" ] || { echo 'Sparkle archive checksum mismatch' >&2; exit 1; }
    tar -xJf "$archive" -C "$tool_dir"
fi
printf '%s\n' "$tool_dir"
