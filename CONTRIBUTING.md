# Contributing

Build with `./build.sh` and run `./test.sh`. Tests must use temporary local stores and simulated Gmail responses, never a contributor's live mailbox.

Report the macOS version, the action that failed, and the expected result. Use fictional addresses in screenshots. Do not attach OAuth JSON, tokens, mail-cache.json, certificate exports, private emails, or attachments.

For a safe UI demo:

```sh
POST_DEMO_BUILD=1 ./build.sh
open '.build/Post Demo.app'
```

The demo has its own bundle identifier, uses fictional messages and an isolated temporary cache, does not read the live Gmail Keychain items, and disables Gmail connection. It resets the sample data on launch. It includes a three-message conversation with an outgoing reply. Demo captures should come from this build.

Use plain text in the UI, rounded rectangular controls, and the shared adaptive colors. Keep keyboard shortcuts and accessibility labels in sync. Check Light and Dark appearance, typing focus, Escape and Return in prompts, and the empty selection state when changing interaction code.
