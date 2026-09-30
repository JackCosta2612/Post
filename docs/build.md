# Build Post on your Mac

## Prerequisites

Use macOS 14 or later. Install Apple's Command Line Tools with `xcode-select --install`, or install Xcode and select its toolchain. Swift 5.9 or later is required. Accept any Apple license yourself when prompted. The build uses SwiftUI, AppKit, WebKit, Security, Network, and UserNotifications from the macOS SDK.

## Local signing

Run these commands inside the cloned repository:

```sh
./setup-signing.sh
./build.sh
open ../Post.app
```

`setup-signing.sh` creates a self-signed certificate named **Post Local Development** with a private key in your login Keychain. It grants the system `codesign` tool access to that key. It creates no Apple account, does not change system certificate trust, and does not disable Gatekeeper. Temporary certificate files are deleted when the script exits. Keep that identity on your own Mac; do not share or commit it.

macOS may ask for your login Keychain password to let `codesign` use the key. Confirm that the request is for **Post Local Development** and `/usr/bin/codesign`. Choosing Always Allow for that specific key avoids a signing prompt on every build. The first signed Post build may also ask to access its existing Google client and token items. Authorize Post for those items. Later builds use the same app identifier and certificate, so their identity remains stable.

If the Keychain itself is locked, it can still require unlocking. Replacing or deleting the signing certificate changes the identity and can require authorization again.

```sh
./test.sh
./build.sh
codesign --verify --deep --strict ../Post.app
codesign -d -r- ../Post.app
```

The designated requirement should reference `com.jack.Post` and a certificate fingerprint, not a build-specific `cdhash`. Rebuild twice and compare that requirement if investigating repeated prompts.

For a temporary sample or CI build, `POST_SIGNING_IDENTITY=- ./build.sh` uses ad hoc signing. Every edited ad hoc build has a new identity, so this is unsuitable for avoiding Gmail Keychain prompts.

Set `POST_SIGNING_IDENTITY` to use another code-signing identity you already own. `POST_APP_OUTPUT` changes the app's output location.

## Xcode

Open `Post.xcodeproj` after setting up the local certificate. The project uses manual signing with **Post Local Development**. Select a different identity in Signing & Capabilities if needed. The command-line build is the verified build path.

## Icon

The editable layered icon is `Post.icon`. Compiled `Resources/Assets.car` and `Resources/Post.icns` are checked in, so a normal build does not require Icon Composer. To edit it, use Apple's Icon Composer. With Xcode's icon tooling installed, run `./build-icon.sh` to recompile the catalog. The fallback `.icns` must also be regenerated if you change the design.

## Sharing with friends

Share the repository URL and have each person build locally and follow the Gmail guide. Your local self-signed identity is not a Developer ID signature or Apple notarization. Building on each person's Mac avoids presenting your certificate as a public software-distribution identity.
