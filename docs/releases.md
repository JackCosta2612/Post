# Versions and updates

Post uses semantic versions: major.minor.patch. `VERSION` is the build's version source. Git tags use `v0.2.0` format. The build number is the number of commits at build time. About Post and Settings → Account show the installed version.

Choose Post → Check for updates, or Settings → Account → Check for updates. Post reads the latest published GitHub release and compares its version with the installed app. The check is manual, has no analytics, and sends no mail or account details. It opens release notes when a newer version is available. Updates are not installed automatically.

## Install a newer release

For a cloned checkout:

```sh
git fetch --tags
git checkout v0.2.1
./build.sh
# Quit Post before installing.
./install.sh
```

Replace the tag with the latest version from Releases. Reuse the same local signing certificate to keep the app identity stable. Account data stays in Keychain and Application Support.

## Publish a release

1. Change `VERSION` and the matching version in `Info.plist`.
2. Update `RELEASE_NOTES.md`, `CHANGELOG.md`, and the README release badge and link.
3. Run the checks, build, and review the app. Commit the changes.
4. Tag the commit with `v` followed by `VERSION`, then push that tag.

The release workflow validates the tag/version match, runs tests, builds and verifies an app, then publishes a source archive with the release notes. A failed check prevents publication. Source releases support both Intel and Apple Silicon through local builds. Developer ID signing and notarized downloadable apps are a separate distribution decision.
