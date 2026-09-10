# Contributing

DuoLid is a Swift 6 / macOS 14+ application. Open `Package.swift` in Xcode or use the Swift command line. Contributions are MIT licensed under the repository license.

Start with `swift test -c release -Xswiftc -warnings-as-errors`. Keep changes focused and explain the user-visible problem, behavior after the change, and relevant validation. Add behavioral tests for lifecycle, timing, settings, or audio changes. Cosmetic edits do not need tests that merely duplicate view structure.

Do not run a full-screen diagnostic on someone else's working display. The current pink-screen incident is unresolved. `--settings-only` disables all Metal previews and desktop effects without changing saved preferences. The safety interlock must remain in place until supported by live evidence.

Never commit captured desktop pixels, raw crash logs, signing certificates, private keys, account credentials, build artifacts, or notarization logs. Share Settings → Copy diagnostics when useful; inspect it before submitting. Website media must use synthetic content through the actual renderer.

Render resources belong to one render owner. New callback state needs a documented synchronization boundary; do not suppress Swift 6 warnings or blanket-mark mutable UI state as Sendable. Preserve the production bundle identifier and preference keys. New settings must migrate without resetting independent choices.

Read [architecture](docs/ARCHITECTURE.md), [verification](docs/VERIFICATION.md), and [compatibility](docs/COMPATIBILITY.md). CI checks source and both CPU architectures; physical lid, graphics, permissions, and installation behavior require a real Mac and a human operator.
