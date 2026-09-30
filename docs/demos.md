# Demo recording

[Watch or download Post’s demo](media/post-demo.mp4). The video also plays at the top of the repository README.

The 1 minute 46 second video records the native Post Demo app with fictional mail. It shows opening mail, Down-arrow navigation, scrolling a conversation, expanding quoted text, replying, saving a draft, opening and deleting that draft, collapsing the sidebar, and switching between light and dark appearance.

The reply was typed letter by letter. Idle gaps were trimmed. Cursor movements, click rings, and keyboard indicators were added from the recorded action times. The cream background, rounded window framing, and shadow were applied during editing. No live Gmail account, private message, credentials, or attachment appears in the recording.

## Record another take

Build the isolated demo described in [Contributing](../CONTRIBUTING.md). It uses a separate bundle identifier and sample mailbox, starts in light mode, and opens a 1670 × 920 window.

For a native window capture, compile the helper on macOS 15 or later:

```sh
swiftc -parse-as-library scripts/record-demo.swift -o /tmp/post-demo-recorder
/tmp/post-demo-recorder /tmp/post-demo.mp4 /tmp/post-demo.stop
```

Grant screen recording permission if macOS asks. Create `/tmp/post-demo.stop` to finish recording. Remove an existing stop file before starting another take. This helper records only the Post Demo window, including its sheets, at 60 fps without audio or the system cursor. Post itself still supports macOS 14.

With FFmpeg and Python Pillow installed, frame the capture and add action indicators:

```sh
python3 scripts/edit-demo.py /tmp/post-demo.mp4 /tmp/timeline.json /tmp/post-demo-edited.mp4
```

The timeline has a `start` Unix timestamp and an `events` array. Each event has an `at` timestamp, a `kind` (`click`, `key`, `typing`, `typingEnd`, or `end`), a `point` in capture pixels or `null`, and a `label` for the keyboard indicator. Include one `typing` event and one `typingEnd` event to delimit the reply entry. Use times from the actual interaction. Review the entire edited video before publishing it.

The older `mailbox-demo.mp4` and `dark-mode-demo.mp4` files are captioned app captures, retained as earlier documentation examples.
