# Local release process

The planned first release is **0.9.0-beta.1**. Stable **1.0.0** requires the additional hardware/OS matrix. The current display incident is unresolved. Do not publish while `docs/release/acceptance.json` contains blockers.

## Identity, keys, and inputs

Production uses `app.duolid.DuoLid`, team `PPK4QC7R3L`, and `Developer ID Application: Tejas Agrawal (PPK4QC7R3L)`. The release build fails if that exact identity is unavailable. Development has a different identifier and ad-hoc signature. Do not change the production identity to work around Screen Recording permission problems.

Sparkle 2.9.6 is pinned by version, commit, and binary checksum through SwiftPM. Its Ed25519 private key is stored in the local login Keychain under account `app.duolid.DuoLid`. Only the public key is embedded. Keep an encrypted offline recovery backup using Sparkle's documented key export procedure; never put it in this repository or CI.

In a local interactive Terminal, run:

```sh
bash scripts/notary-credentials.sh
```

Apple's tool prompts for the Apple Account and app-specific password and stores the validated credentials under profile `DuoLid-notary`. Enter secrets locally. Do not paste them into chat, shell arguments, environment files, GitHub secrets, or this repository. The Developer ID certificate by itself is not a notarization credential.

Set version and monotonically increasing build number in `Resources/Info.plist`; update the changelog and release-note draft. Commit all source and packaging changes. Release builds require a clean checkout. Xcode's Metal Toolchain is needed (`xcodebuild -downloadComponent MetalToolchain`).

## Candidate packaging

```sh
bash scripts/package-release.sh
```

This checks the Keychain profile, builds both macOS 14 slices with strict Swift 6 checks, precompiles Metal, embeds Sparkle, signs nested helpers before the app, and statically verifies architectures/resources/signatures. It then:

1. Submits a ZIP of the app to Apple's notary service and waits for acceptance.
2. Staples and validates the app; checks Gatekeeper execution assessment.
3. Creates a DMG containing the stapled app and Applications shortcut.
4. Signs, notarizes, staples, and assesses the DMG.
5. Creates the final ZIP from the stapled app.
6. Generates signed archives/appcast with Sparkle using the Keychain key, and SHA-256 checksums.
7. Records toolchain, source revision, dependency hash, architecture, version/build, and Apple submission results locally.

Candidate files live under ignored `dist/candidates/VERSION-BUILD/`. Existing candidates are never silently overwritten. Inspect failed submissions with `xcrun notarytool log`; preserve failed artifacts and use a higher build for a fresh candidate. A timestamped Apple signature and stapled ticket are not byte-reproducible. The build inputs and metadata are explicit and pinned; checksums identify the exact distributed files.

The generated signed feed must be deployed byte-for-byte. Editing it invalidates the signature. These signatures do not expire with time. DuoLid sets `SUSignedFeedFailureExpirationInterval` to `0`, so an invalid feed remains rejected instead of entering Sparkle's default recovery mode after 20 days of validation failures. This enforces signed feeds throughout the update flow. Losing the signing key therefore requires a manually downloaded Developer ID signed, notarized replacement, unless a key transition was signed with the old key beforehand. See [Sparkle's security settings](https://sparkle-project.org/documentation/customization/). Keep the encrypted recovery backup outside Git.

## Acceptance and publication

On a designated test Mac, complete the [verification gates](VERIFICATION.md), including quarantined browser installation, offline launch, first permission grant, and signed update/tamper/interruption tests. Use a test feed and disposable installation with a distinct identity for destructive update testing; never replace an installed user's app with a test archive.

Record the tested commit, evidence and results in `docs/release/acceptance.json`. Documentation-only commits after acceptance are allowed; changed shipped inputs invalidate it. The publication script refuses missing checks, unresolved blockers, dirty trees, stale candidate inputs, reused versions, and non-increasing builds.

```sh
bash scripts/publish-release.sh dist/candidates/0.9.0-beta.1-90001
```

The script tags the candidate commit, creates a draft prerelease, uploads the verified DMG/ZIP/checksums/provenance/appcast, downloads and compares those assets, and makes the release public. Only then does it commit the exact signed appcast and the website's explicit versioned download URL. GitHub Pages deploys the separate `site/` directory. The beta does not use `/releases/latest`, which excludes prereleases.

All signing remains local. GitHub Actions receives no private keys or notarization credentials. CI builds/tests Apple silicon and Intel and deploys static website files.

## Channels and withdrawal

The single appcast has a `beta` channel; the unchanneled default is stable. Beta builds opt into beta updates initially; stable builds require the user's beta preference. Stable entries remain visible to both. Automatic checks are opt-in, system profiling is disabled, and installation requires user interaction.

To withdraw a release, remove its item from the feed, regenerate the feed signature, restore the previous explicit website download metadata, and deploy. Preserve published artifacts and history. Correct installed users with a newly signed release whose build number is higher. Do not reuse an existing archive URL with changed bytes.
