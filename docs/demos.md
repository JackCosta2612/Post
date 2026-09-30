# Demo walkthroughs

The MP4s show the running native Post Demo build using fictional mail. They use captioned app captures rather than real-time screen recordings. No live Gmail account, private message, OAuth file, or attachment is shown.

## Mailbox and conversation

[Watch mailbox-demo.mp4](media/mailbox-demo.mp4)

1. Labels and a focused Primary inbox.
2. A three-message conversation, including a sent reply.
3. Scroll through the conversation without opening separate windows.
4. Command + R opens a reply and focuses the body.

## Dark mode and drafts

[Watch dark-mode-demo.mp4](media/dark-mode-demo.mp4)

1. Dark appearance in Settings; Light and System are also available.
2. Collapsed sidebar and Shift-arrow bulk selection without checkboxes.
3. A saved reply draft opens in the reading pane.

## Recreate captures

Build the isolated demo described in [Contributing](../CONTRIBUTING.md). Capture only that app's window in the states above and save the PNGs under `docs/demo-frames` as `01-inbox.png` through `07-drafts.png`. That directory is ignored by Git. With FFmpeg and the Python Pillow package installed, run `python3 scripts/render-demos.py` to produce the videos and README images. FFmpeg is only required for this documentation step, not to build Post.
