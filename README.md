# Post

A native SwiftUI email client for macOS and one Gmail account. Labels, keyboard navigation, and a quiet three-pane layout are the focus.

https://github.com/user-attachments/assets/9e444f02-44cd-43bf-888f-ac5bf4f9d46a

[Download the preview](docs/media/post-demo.mp4)

![Post in light and dark mode](docs/media/appearance.png)

## Try it

Requires macOS 14 or later and Apple's Command Line Tools or Xcode. There are no package dependencies and no paid Apple developer membership is needed for a local build.

```sh
git clone https://github.com/JackCosta2612/Post.git
cd Post
./setup-signing.sh
./build.sh
./install.sh
open /Applications/Post.app
```

The app starts with fictional sample mail until you connect Gmail. Follow the [Gmail setup guide](Setup.md) for your own Google Cloud project and Desktop OAuth client. Each person connects their own account; no shared OAuth credentials are bundled.

See [build and signing instructions](docs/build.md) for prerequisites, Keychain prompts, Xcode, and rebuilding the icon.

## Features

- Light, Dark, or System appearance, custom accent colors, adjustable text size and density, and optional bold unread messages.
- Customize label visibility, numbered badges, and unread or total counts in Settings → Sidebar. Drag labels to reorder them; Primary stays first. Mail filters stay pinned at the bottom while overflowing labels scroll above them.
- Undo Send with a configurable delay, local scheduled sending, and a rich text composer with custom fonts, colors, and formatting.
- Configurable read delay, conversation grouping, label shortcuts, notification filters and quiet hours.
- Balanced or Faster caching for messages, threads, images, and attachments. See [Settings](docs/settings.md).
- Drag one message or a selection onto a label to move it, onto Primary to return it to the inbox, or onto Trash to discard it. Moves can be undone.
- Primary includes unlabeled inbox mail. Choose multiple labels to include in Settings → Inbox; custom labels and Promotions are excluded by default, including newly created labels. Gmail's own Primary category is also available.
- Conversations show incoming mail and sent replies in chronological order. They open at the selected message, with quoted replies collapsed and a reply control on each message.
- Shift-click, Command-click, and Shift-arrow selection. Bulk label, archive, and Trash without checkboxes.
- Compose, reply, reply all, forward, attachments, autosaved drafts, and confirmed draft deletion.
- Search filtering and highlighting in the loaded list, labels, read status, stars, spam, reversible Trash, and Undo for local mail actions.
- Saved lists for each folder show immediately on return visits and refresh quietly.
- Local cache for offline reading. Embedded images resolve locally; external images are blocked by default.
- Background checking every 60 seconds while running. The loading strip appears only for manual refresh.
- New-mail notifications for Primary or All mail, with optional sound and sender/subject previews.
- Custom shortcuts update menus and on-screen hints.

## Default keys

| Action | Key |
| --- | --- |
| Next / previous message | Down / Up |
| Extend selection | Shift + Down / Up |
| Reply / reply all | Command + R / Command + Shift + R |
| Compose | Command + N |
| Label / archive / Trash | L / E / Delete |
| Clear selection | Escape |
| Search | Command + F |
| Refresh | Command + Shift + Option + R |
| Toggle sidebar | Command + S |

Typing keeps normal cursor and editing behavior. Escape after editing a reply offers Save, Discard changes, or Keep writing. Return activates a prompt's default action; Escape cancels it.

## Data and limitations

OAuth credentials stay in macOS Keychain. Cached messages, drafts, schedules, and preferences live in `~/Library/Application Support/Post/mail-cache.json`. Faster mode stores downloaded attachment bytes separately in `AttachmentCache`; remote images use `RemoteImages` under the same folder. The cache is local JSON, not a separately encrypted database. Remote attachment bytes are fetched when needed. Attachment clicks download directly to Downloads, with a configurable destination in Settings. HTML runs without sender-provided JavaScript.

Disconnecting removes the sign-in token but keeps cached mail. To remove local mail too, quit Post and remove its Application Support folder. Revoke the authorization in your Google account if you no longer use the app.

Post is an early client under active development. It supports one account at a time. Pagination loads more mail on demand; it does not download your entire account at startup. Notifications and synchronization require the app to be running. Composition is plain text with a formatted quoted message. There is no AI sorting, encrypted-email support, background daemon, or notarized binary release. The source and native layered icon are included.

## Development

```sh
./test.sh
./build.sh
```

Tests use fictional data and simulated Gmail responses. The [contributing guide](CONTRIBUTING.md) describes bug reports and local testing. MIT licensed.
