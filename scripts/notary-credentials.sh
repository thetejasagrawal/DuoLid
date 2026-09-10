#!/bin/bash
set -euo pipefail
# Run locally in an interactive Terminal. Apple prompts for credentials; do not
# pass an app-specific password in command-line arguments, Git, CI, or chat.
exec xcrun notarytool store-credentials 'DuoLid-notary' --team-id PPK4QC7R3L
