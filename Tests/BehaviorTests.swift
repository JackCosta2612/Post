import Foundation

@main
struct BehaviorTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ result: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            guard result() else { fatalError("FAILED: \(name)") }
        }
        check(MessageQuote.split("Hello\n\nOn Tuesday, Alex wrote:\n> Previous").body == "Hello", "Reply header is folded with quote")
        check(MessageQuote.split("Hello\n> Previous").quote == "> Previous", "Plain quoted lines remain expandable")
        check(MessageQuote.split("Unquoted message").quote == nil, "Unquoted content stays visible")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PostTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MailStore(directory: directory)
        check(store.visibleMessages.count == 5, "Primary excludes confirmations and rejections")
        check(store.folders.first { $0.id == "primary" }?.unreadCount == 4, "Unread badges count unread messages")
        check(store.folders.first { $0.id == "primary" }?.totalCount == 5, "Total badges include read messages")
        var update = store.messages[0]; update.id = "update"; update.labels = ["INBOX", "CATEGORY_UPDATES", "UNREAD"]
        check(store.contains(store.folder, update), "Primary includes Updates by default")
        update.labels.insert("CATEGORY_PROMOTIONS")
        check(!store.contains(store.folder, update), "Primary excludes Promotions")
        update.labels = ["INBOX", "newsletters"]
        check(!store.contains(store.folder, update), "Primary excludes Newsletter-labelled inbox mail")
        var trashed = update; trashed.labels = ["TRASH", "rejections"]
        let rejectionFolder = store.folders.first { $0.id == "rejections" }!
        check(!store.contains(rejectionFolder, trashed), "Trashed mail disappears from custom labels")
        store.messages.append(trashed); store.connected = true; store.currentRemoteIDs = [trashed.id]
        store.folderID = "rejections"
        check(store.visibleMessages.isEmpty, "Stale remote result IDs cannot resurrect trashed mail")
        store.connected = false; store.currentRemoteIDs = nil; store.folderID = "primary"
        store.messages.removeAll { $0.id == trashed.id }
        store.preferences.markRead = false
        store.navigate(1)
        let first = store.selectedID!
        check(first == "sample-0", "Down from no selection picks first message")
        store.navigate(1)
        check(store.selectedID == "sample-1", "One navigation advances exactly one item")
        store.select(nil)
        check(store.selected == nil && store.conversation.isEmpty, "Escape state has no selected message or preview")
        check(store.folders.first { $0.id == "primary" }?.unreadCount == 4, "Clearing selection preserves unread state")
        store.select(first)
        store.actOnSelected(add: ["confirmations"], remove: ["INBOX"])
        check(!store.visibleMessages.contains { $0.id == first }, "Label and archive removes mail from Primary")
        store.chooseFolder("confirmations")
        check(store.visibleMessages.contains { $0.id == first }, "Archived message remains under its label")
        store.undo()
        store.chooseFolder("primary")
        check(store.visibleMessages.contains { $0.id == first }, "Undo restores original labels")
        store.select(first)
        store.actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true)
        check(store.selectedID == "sample-1", "Trash advances selection to the adjacent item")
        store.chooseFolder("TRASH")
        check(store.visibleMessages.count == 1, "Trash remains recoverable")
        store.preferences.totalCounts = true
        store.preferences.collapsed = true
        check(store.setShortcut("reply", value: .init(key: "j", command: true)), "Custom shortcut accepted")
        check(!store.setShortcut("label", value: .init(key: "j", command: true)), "Conflicting shortcut rejected")
        store.error = nil
        var draft = ComposeDraft(to: "recipient@example.com", subject: "Candidatura ricevuta", body: "Hello,\nThis is a test.")
        draft.attachments = [.init(id: "attachment", name: "file.txt", mimeType: "text/plain", size: 3, data: Data("abc".utf8))]
        store.saveDraft(draft, sync: false)
        let reloaded = MailStore(directory: directory)
        check(reloaded.preferences.totalCounts && reloaded.preferences.collapsed, "Preferences survive relaunch")
        check(reloaded.preferences.shortcuts["reply"]?.display == "⌘J", "Custom shortcut persists")
        check(reloaded.drafts.first?.attachments.first?.data == Data("abc".utf8), "Local draft and attachment survive relaunch")
        let raw = String(data: try MIMEBuilder.build(draft, from: "sender@example.com"), encoding: .utf8)!
        check(raw.contains("Content-Disposition: attachment; filename=\"file.txt\""), "MIME attachment generated")
        check(raw.contains("Subject: =?UTF-8?B?"), "Unicode subject encoded")
        draft.subject = "Hello\r\nBcc: attacker@example.com"
        let safe = String(data: try MIMEBuilder.build(draft, from: "sender@example.com"), encoding: .utf8)!
        check(!safe.contains("\r\nBcc: attacker"), "Header injection is blocked")
        let data = Data([0, 255, 254, 253, 128, 1])
        check(Data(base64URL: data.base64URL) == data, "Base64URL round trip")
        let json: [String: Any] = ["id": "gmail-message", "threadId": "thread", "labelIds": ["INBOX", "UNREAD"], "internalDate": "1000", "payload": ["mimeType": "multipart/mixed", "headers": [["name": "From", "value": "Alice <alice@example.com>"], ["name": "Subject", "value": "An email"]], "parts": [["mimeType": "text/plain", "body": ["data": Data("Real body".utf8).base64URL]], ["filename": "image.png", "mimeType": "image/png", "body": ["attachmentId": "download-id", "size": 200]]]]]
        let parsed = try GmailClient.parseMessage(json)
        check(parsed.body == "Real body" && parsed.senderAddress == "alice@example.com", "Gmail MIME parser preserves body and sender")
        check(parsed.attachments.first?.messageID == "gmail-message", "Forwarded attachments retain source identity")
        check(Shortcut.parse("cmd+shift+r") == .init(key: "r", command: true, shift: true), "Modifier parsing")
        var legacy = ComposeDraft(body: "My reply\n\nOn 30 Sep 2026, Alice wrote:\n> Original message\n> \n> Second paragraph")
        legacy.separateLegacyQuote()
        check(legacy.body == "My reply" && legacy.quotedText == "Original message\n\nSecond paragraph", "Old drafts separate editable reply from formatted quote")
        legacy.to = "alice@example.com"; legacy.quotedHTML = "<strong>Original message</strong>"
        let quotedMIME = String(data: try MIMEBuilder.build(legacy, from: "sender@example.com"), encoding: .utf8)!
        check(quotedMIME.contains("multipart/alternative") && quotedMIME.contains("text/html; charset=UTF-8"), "Reply sends both plain text and formatted HTML")
        check(quotedMIME.contains(Data((legacy.body + "\n\n" + legacy.quoteHeading! + "\n" + legacy.quotedText!).utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])), "Outgoing reply preserves quoted content")
        store.chooseFolder("primary"); store.select("sample-1"); store.newCompose(kind: "reply")
        check(store.compose?.quotedText == store.selected?.body && !(store.compose?.body.contains("> Hi") ?? true), "New replies keep quote separate from editable text")
        store.compose = nil
        var second = ComposeDraft(to: "second@example.com", subject: "Second draft", body: "Second")
        second.quotedText = "Previous"; second.quotedHTML = "<b>Previous</b>"
        store.saveDraft(second, sync: false); store.chooseFolder("DRAFT"); store.navigate(1)
        check(store.selectedDraftID == draft.id, "Draft navigation starts with first draft")
        store.navigate(1)
        check(store.selectedDraftID == second.id, "Draft navigation selects the next editor")
        store.perform("clear")
        check(store.selectedDraftID == nil, "Escape deselects the draft editor")
        store.selectedDraftID = second.id; store.deleteDraft(second); store.saveDraft(second, sync: false)
        check(store.selectedDraftID == nil && !store.drafts.contains { $0.id == second.id }, "Deleted draft cannot be recreated by delayed autosave")
        let afterDeletion = MailStore(directory: directory)
        check(!afterDeletion.drafts.contains { $0.id == second.id }, "Draft deletion survives relaunch")
        check(afterDeletion.folders.first { $0.id == "DRAFT" }?.totalCount == 1, "Draft count updates after deletion")
        let multi = MailStore(directory: directory.appendingPathComponent("Multi"))
        multi.preferences.markRead = false
        multi.select("sample-0"); multi.extendNavigation(1); multi.extendNavigation(1)
        check(multi.bulkIDs == ["sample-0", "sample-1", "sample-2"] && multi.selected == nil, "Shift arrows select a range with no reading preview")
        multi.extendNavigation(-1)
        check(multi.bulkIDs == ["sample-0", "sample-1"], "Reversing Shift arrows shrinks the range")
        multi.clickMessage("sample-4", command: true)
        check(multi.bulkIDs == ["sample-0", "sample-1", "sample-4"], "Command click adds a nonadjacent message")
        multi.clickMessage("sample-1", command: true)
        check(multi.bulkIDs == ["sample-0", "sample-4"], "Command click toggles one message off")
        multi.select("sample-1"); multi.clickMessage("sample-4", shift: true)
        check(multi.bulkIDs == ["sample-1", "sample-2", "sample-3", "sample-4"], "Shift click selects the anchored range")
        multi.actOnSelected(add: ["confirmations"], remove: ["INBOX"], advance: true)
        check(multi.visibleMessages.map(\.id) == ["sample-0"] && !multi.bulkMode, "Bulk move removes every selected message from Primary and clears selection")
        check(multi.messages.filter { ["sample-1", "sample-2", "sample-3", "sample-4"].contains($0.id) }.allSatisfy { $0.labels.contains("confirmations") }, "Bulk move applies the destination label to all messages")
        multi.undo()
        check(multi.visibleMessages.count == 5, "One Undo restores the entire bulk move")
        multi.select("sample-0"); multi.clickMessage("sample-2", command: true)
        multi.actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true)
        check(multi.messages.filter { $0.labels.contains("TRASH") }.count == 2, "Bulk Trash acts only on selected messages")
        multi.undo(); multi.select("sample-0"); multi.clickMessage("sample-2", command: true); multi.perform("clear")
        check(multi.bulkIDs.isEmpty && multi.selectedID == nil && !multi.bulkMode, "Escape clears the complete multi-selection")
        multi.select("sample-0"); multi.clickMessage("sample-2", command: true); multi.navigate(1)
        check(!multi.bulkMode && multi.selectedID == "sample-3", "Plain arrows resume single-message reading")
        multi.clickMessage("sample-4", command: true); multi.chooseFolder("confirmations")
        check(multi.actionIDs.isEmpty && !multi.bulkMode, "Changing folders clears bulk selection")
        let draftSelection = MailStore(directory: directory.appendingPathComponent("DraftSelection"))
        let draftGroup = (0..<5).map { ComposeDraft(to: "person\($0)@example.com", subject: "Draft \($0)", body: "Original \($0)") }
        for value in draftGroup { draftSelection.saveDraft(value, sync: false) }
        draftSelection.chooseFolder("DRAFT"); draftSelection.clickMessage(draftGroup[0].id); draftSelection.extendNavigation(1); draftSelection.extendNavigation(1)
        check(draftSelection.bulkIDs == Set(draftGroup.prefix(3).map(\.id)) && draftSelection.selectedDraftID == nil, "Shift arrows select drafts and close the single editor")
        draftSelection.extendNavigation(-1)
        check(draftSelection.bulkIDs == Set(draftGroup.prefix(2).map(\.id)), "Shift arrows shrink the draft range")
        draftSelection.clickMessage(draftGroup[4].id, command: true)
        check(draftSelection.bulkIDs.count == 3 && draftSelection.bulkIDs.contains(draftGroup[4].id), "Command click adds a nonadjacent draft")
        draftSelection.clickMessage(draftGroup[0].id, command: true)
        check(!draftSelection.bulkIDs.contains(draftGroup[0].id), "Command click removes a draft")
        draftSelection.select(draftGroup[1].id); draftSelection.clickMessage(draftGroup[3].id, shift: true)
        check(draftSelection.bulkIDs == Set(draftGroup[1...3].map(\.id)), "Shift click selects a draft range")
        draftSelection.perform("trash")
        check(draftSelection.draftsToDelete.count == 3 && draftSelection.drafts.count == 5, "Bulk draft deletion requires confirmation before deleting")
        for value in draftSelection.draftsToDelete { draftSelection.deleteDraft(value) }
        check(draftSelection.drafts.count == 2 && !draftSelection.bulkMode, "Confirmed group deletion removes every selected draft")
        draftSelection.select(draftGroup[0].id); draftSelection.clickMessage(draftGroup[4].id, command: true); draftSelection.perform("clear")
        check(draftSelection.actionIDs.isEmpty && draftSelection.selectedDraftID == nil, "Escape clears bulk drafts")
        var untouched = ComposeDraft(to: "alice@example.com", subject: "Re: Subject", body: "\n\nMy signature")
        untouched.quotedText = "Original mail"; untouched.quoteHeading = "Alice wrote:"
        check(!untouched.hasUserChanges(from: untouched), "Generated recipients, subject, signature and quote do not create a draft")
        var edited = untouched; edited.body = "My reply" + untouched.body
        check(edited.hasUserChanges(from: untouched), "Typing a reply requires a save decision")
        edited = untouched; edited.attachments = [.init(id: "new", name: "file.txt", mimeType: "text/plain", size: 3, data: Data("abc".utf8))]
        check(edited.hasUserChanges(from: untouched), "Adding an attachment requires a save decision")
        edited = untouched; edited.body += "  \n"
        check(!edited.hasUserChanges(from: untouched), "Whitespace alone does not create an empty reply draft")
        var embedded = store.messages[0]; embedded.id = "embedded"; embedded.html = "<img src=\"cid:logo\">"
        embedded.attachments = [.init(id: "img", name: "logo.png", mimeType: "image/png", size: 3, data: Data([1,2,3]), contentID: "logo")]
        store.merge([embedded])
        check(store.messages.first { $0.id == "embedded" }!.html.contains("data:image/png;base64,AQID"), "Inline data renders as soon as it enters the cache")
        embedded.attachments[0].data = nil
        store.merge([embedded])
        let retained = store.messages.first { $0.id == "embedded" }!
        check(retained.html.contains("data:image/png;base64,AQID") && retained.attachments[0].data != nil, "History refresh preserves previously downloaded inline images")
        let threadStore = MailStore(directory: directory.appendingPathComponent("threads"))
        threadStore.preferences.markRead = false
        let incoming = threadStore.messages[0]
        var outgoing = incoming; outgoing.id = "outgoing"; outgoing.from = "Alex <alex@example.com>"; outgoing.to = "team@northpeak.example"; outgoing.labels = ["SENT"]; outgoing.date = incoming.date.addingTimeInterval(60)
        threadStore.messages += [outgoing]
        threadStore.select(incoming.id)
        check(threadStore.threadMessages.map(\.id) == [incoming.id, outgoing.id], "Conversation includes sent replies in chronological order")
        threadStore.newCompose(kind: "reply", replyingTo: outgoing)
        check(threadStore.compose?.to == "team@northpeak.example", "Replying to your sent message addresses the other participant")
        threadStore.preferences.appearance = "dark"; threadStore.persist()
        let darkStore = MailStore(directory: directory.appendingPathComponent("threads"))
        check(darkStore.preferences.appearance == "dark", "Appearance choice persists")
        print("PASS: \(checks) behavioral checks")
    }
}
