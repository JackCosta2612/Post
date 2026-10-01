# Settings

Post’s settings are grouped by task:

| Section | Controls |
| --- | --- |
| Appearance | System, light or dark mode; preset or custom accent; list text size, density and bold unread text |
| Inbox | Primary categories and included labels |
| Sidebar | Badge visibility, unread or total counts, label visibility and drag order |
| Reading | Conversation grouping, read delay, font, text size and remote images |
| Composing | Default font, size, color, spacing and signature |
| Sending | Undo Send delay and scheduled delivery behavior |
| Notifications | Primary, all mail or selected labels; sender allowlist; quiet hours; sound; sender, subject and excerpt visibility; foreground banners |
| Shortcuts | Action shortcuts, label shortcuts and bottom hint visibility |
| Storage & downloads | Cache mode, local size, clearing downloaded media and attachment destination |
| Account | Gmail connection and setup |

## Sending

Undo Send defaults to five seconds and can be turned off or set to 10, 20 or 30 seconds. The message stays on this Mac until that delay ends. Undo Send restores the composer.

Choose the clock beside Send to schedule a message. Scheduled mail appears in Drafts. Opening it cancels its schedule so you can edit it, send it, or choose another time.

Post must be running to send queued mail. Overdue messages send after reopening and reconnecting to Gmail. If a send is interrupted or not confirmed, Post keeps the draft for review and does not retry it automatically. Check Gmail’s Sent folder before sending again.

Schedules belong to this Mac. Gmail’s website and other clients cannot manage them.

## Reading and navigation

Conversation subjects stay above the scrolling messages. Assigned labels appear below the subject. Turning conversation grouping off displays only the selected message.

Read delay defaults to immediate. Leaving a message before the delay expires cancels its read timer. With grouping enabled, opening a conversation marks its messages as read after the delay.

Command + 1 through Command + 9 open visible sidebar labels by default. Record a different Command shortcut in Settings → Shortcuts. Label navigation works only with no selected message, composer, or focused text field. Hold Command in that state to see the assigned keys.

Drag labels in the live sidebar or use handles in Sidebar settings to reorder them. Primary stays first. Message drags move mail to a label, Primary, or Trash. Drag previews are translucent, and a ten-point movement threshold avoids accidental drags.

## Cache modes

Balanced is the default and retains the previous limits: up to 40 rendered messages, 32 MB of image memory cache and 128 MB of image disk cache.

Faster retains up to 120 rendered messages, 128 MB of image memory cache and 1 GB of image disk cache. It preloads up to six nearby threads and remote images when automatic image loading is enabled. Opened threads can cache up to 20 MB of attachments each. Downloaded attachment bytes are stored separately so metadata changes do not repeatedly rewrite them.

Faster uses more memory, storage and Gmail requests. These are capacity limits, not guaranteed performance measurements. Server cache directives can prevent an image from being stored. Cached message bodies and drafts remain available offline in both modes.

Clear downloaded media removes cached attachment bytes and remote images. It preserves messages, drafts, settings, inline message content and files already saved to Downloads.

## Notifications

Selected-label notifications match any enabled label. A sender allowlist restricts notifications to the listed email addresses; an empty allowlist accepts all senders. Sender and label filters both apply. Spam, Trash and sent mail never notify.

Quiet hours use your Mac’s local time and can span midnight. Messages received during quiet hours do not produce delayed banners afterward. Post checks for new mail every minute while running; macOS permissions and Focus settings still control delivery.

Interface, composing, and reading fonts have separate controls. Each defaults to SF Pro Display. Interface font is under Appearance; composing and reading fonts are in their respective sections. Existing explicit font choices are preserved.

Dragging a label shows a horizontal insertion line above or below its destination. Message drops still move the mail into the target label.

Email content preserves original colors by default. Enable “Use app colors for email content” under Reading to apply Post’s light/dark recoloring. Hold Command for 1.5 seconds without pressing another key to show label shortcut hints. Composer formatting uses the standard Command-B, Command-I, and Command-U shortcuts; each toggles its formatting.

The header count uses section totals from Gmail. The Unread button beside the section title filters only that section, with independent states for each label. It queries unread mail beyond the initial loaded page.
