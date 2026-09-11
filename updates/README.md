# Signed update feed

The release publisher copies the verified `appcast.xml` here byte-for-byte after the release assets are public. Sparkle reads it over HTTPS from GitHub's raw-content host. The embedded public key verifies the feed and downloaded archive; automatic checking remains opt-in.

`release.json` drives the README download button. Before the first verified release, its state is `preparing` and no appcast is advertised. GitHub Pages and a separate landing page are not required.

Use `scripts/publish-release.sh` after the acceptance gates pass. Do not manually edit a signed feed or point the README at an unpublished asset. See [the release process](../docs/RELEASING.md).
