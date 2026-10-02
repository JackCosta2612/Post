# Versions and updates

Post uses semantic versions in `VERSION` and matching `v` Git tags. About Post and Settings → Account show the installed version and build.

Post 0.2.3 and later uses Sparkle for signed in-app updates. Check manually from the Post menu or Settings → Account. Automatic checks are enabled by default; automatic download and installation are optional. Release notes appear once after launching a newer version. Updates preserve local settings and Gmail credentials.

Install 0.2.3 manually once to enable future updates. Download the universal app archive from GitHub Releases, extract it and move Post to Applications. It supports Apple silicon and Intel Macs on macOS 14 or later. These releases use a local signing certificate, not Apple notarization. macOS may require first-launch approval and Keychain authorization when switching from a locally built copy.

## Publishing

Update `VERSION`, `Info.plist`, the README badge, `CHANGELOG.md` and `RELEASE_NOTES.md`. Run tests, then `./scripts/package-update.sh` on the release Mac. It builds both architectures, verifies the app and signs the archive with the Sparkle key stored in Keychain as `com.jack.Post.updates`. The private key never enters the repository.

Commit the generated `docs/appcast.xml` with the release changes, create the matching tag and push. The Release workflow publishes source. Upload `.build/updates/Post-vVERSION.zip` to the matching GitHub release. The feed points at that version's archive. Keep the local signing certificate and Sparkle key for future releases. Sparkle verifies the archive before extracting it.

For source builds, `build.sh` fetches pinned Sparkle 2.10.0 and verifies its SHA-256. The Xcode project uses the same pinned package version.
