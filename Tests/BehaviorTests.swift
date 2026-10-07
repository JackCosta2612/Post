import Foundation
import AppKit

final class DeliveryMock: URLProtocol, @unchecked Sendable {
    static var sends = 0
    static var fail = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let sending = request.url!.path.hasSuffix("messages/send")
        if sending { Self.sends += 1 }
        let value: [String: Any] = request.url!.path.hasSuffix("profile") ? ["emailAddress": "sender@example.com"] : sending ? ["id": "sent-test", "threadId": "sent-thread"] : ["id": "sent-test", "threadId": "sent-thread", "labelIds": ["SENT"], "payload": ["headers": [["name": "Subject", "value": "Scheduled"]]]]
        let status = sending && Self.fail ? 400 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SearchMock: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let query = components.queryItems?.first { $0.name == "q" }?.value ?? ""
        let value: [String: Any]
        if request.url!.lastPathComponent == "messages" {
            value = ["messages": [["id": query.contains("in:anywhere") ? "remote-trash" : "remote-inbox"]], "nextPageToken": "more"]
        } else {
            let id = request.url!.lastPathComponent
            value = ["id": id, "threadId": id, "labelIds": [id == "remote-trash" ? "TRASH" : "INBOX"], "payload": ["mimeType": "text/plain", "headers": [["name": "Subject", "value": "Server-only match"]], "body": ["data": Data("Remote content".utf8).base64URL]]]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct BehaviorTests {
    @MainActor static func main() async throws {
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
        let downloads = directory.appendingPathComponent("Downloads")
        let firstDownload = try MailStore.writeDownload(Data("first".utf8), name: "../../report.pdf", directory: downloads)
        let secondDownload = try MailStore.writeDownload(Data("second".utf8), name: "report.pdf", directory: downloads)
        check(firstDownload.lastPathComponent == "report.pdf" && firstDownload.deletingLastPathComponent().standardizedFileURL.path == downloads.standardizedFileURL.path, "Attachment filenames stay inside download directory")
        check(secondDownload.lastPathComponent == "report (2).pdf", "Duplicate attachment names receive a suffix")
        let retainedDownload = try Data(contentsOf: firstDownload)
        check(retainedDownload == Data("first".utf8), "Quick downloads do not overwrite existing files")
        let recovery = MailStore(directory: directory.appendingPathComponent("Recovery"))
        var received = recovery.messages[0]
        received.labels = ["INBOX"]; received.threadID = "all-mail-conversation"
        var sent = received; sent.id = "sent-reply"; sent.labels = ["SENT"]
        recovery.messages = [received, sent]; recovery.folderID = "all"; recovery.selectedID = received.id
        check(recovery.visibleMessages.map(\.id) == [received.id], "All mail excludes sent messages from list")
        check(recovery.threadMessages.count == 2, "All mail conversation retains sent replies")
        check(recovery.activeFolderQuery.contains("-in:sent"), "All mail server query excludes sent messages")
        recovery.folders.append(.init(id: "newsletter-test", name: "Newsletters", icon: "tag", query: "label:Newsletters", isCustom: true))
        recovery.folderID = "newsletter-test"
        check(recovery.activeFolderQuery == "label:Newsletters -in:trash -in:spam", "Label pages exclude hidden trash and spam before pagination")
        recovery.folderID = "TRASH"
        check(recovery.activeFolderQuery == "in:trash", "Trash remains queryable")
        recovery.folderID = "primary"
        var notificationMail = recovery.messages[0]
        notificationMail.labels = ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"]
        check(!recovery.notificationMatches(notificationMail), "Primary notifications exclude Promotions")
        notificationMail.labels = ["INBOX", "UNREAD", "CATEGORY_UPDATES"]
        check(recovery.notificationMatches(notificationMail), "Wide Primary notifications include Updates")
        recovery.preferences.notificationScope = "all"
        notificationMail.labels = ["UNREAD", "CATEGORY_PROMOTIONS"]
        check(recovery.notificationMatches(notificationMail), "All mail notifications include incoming mail outside Inbox")
        notificationMail.labels = ["SPAM", "UNREAD"]
        check(!recovery.notificationMatches(notificationMail), "All mail notifications exclude Spam")
        notificationMail.labels = ["SENT", "UNREAD"]
        check(!recovery.notificationMatches(notificationMail), "All mail notifications exclude Sent mail")
        recovery.preferences.markRead = false
        var recoverable = recovery.messages[0]
        recoverable.labels = ["TRASH", "UNREAD"]
        recovery.messages = [recoverable]; recovery.folderID = "TRASH"; recovery.select(recoverable.id)
        recovery.moveSelectedToInbox()
        check(recovery.messages[0].labels == ["INBOX", "UNREAD"], "Move from Trash restores Inbox and preserves unread state")
        recovery.messages[0].labels = ["SPAM", "UNREAD"]; recovery.folderID = "SPAM"; recovery.select(recoverable.id)
        recovery.moveSelectedToInbox()
        check(recovery.messages[0].labels == ["INBOX", "UNREAD"], "Move from Spam restores Inbox and removes Spam")
        let folderCache = MailStore(directory: directory.appendingPathComponent("FolderSnapshots"))
        folderCache.connected = true
        folderCache.chooseFolder("CATEGORY_PROMOTIONS")
        check(folderCache.visibleMessages.isEmpty, "Unloaded remote folder does not flash provisional cached mail")
        let promotion = MailStore.samples().first { $0.labels.contains("CATEGORY_PROMOTIONS") }!
        folderCache.folderSnapshots[folderCache.folderCacheKey] = FolderSnapshot(ids: [promotion.id], nextPage: "promotions-page-2")
        folderCache.restoreFolderSnapshot()
        check(folderCache.visibleMessages.map(\.id) == [promotion.id], "Visited folder restores only its own fetched messages")
        folderCache.chooseFolder("newsletters")
        check(folderCache.visibleMessages.isEmpty && folderCache.nextPage == nil, "Folder switch does not reuse another folder list or pagination")
        folderCache.folderSnapshots[folderCache.folderCacheKey] = FolderSnapshot(ids: [], nextPage: nil)
        folderCache.chooseFolder("CATEGORY_PROMOTIONS")
        check(folderCache.nextPage == "promotions-page-2", "Pagination is restored with its folder")
        folderCache.loadTask?.cancel(); folderCache.persist(); folderCache.flushCache()
        let restoredFolders = MailStore(directory: folderCache.directory)
        restoredFolders.connected = true; restoredFolders.chooseFolder("newsletters")
        check(restoredFolders.visibleMessages.isEmpty, "Authoritative empty folder survives app restart")
        restoredFolders.chooseFolder("CATEGORY_PROMOTIONS")
        check(restoredFolders.visibleMessages.map(\.id) == [promotion.id], "Folder list survives app restart")
        restoredFolders.loadTask?.cancel()
        let searching = MailStore(directory: directory.appendingPathComponent("Search"))
        var inboxMatch = searching.messages[0]; inboxMatch.id = "local-inbox"; inboxMatch.subject = "Needle"; inboxMatch.labels = ["INBOX"]
        var trashMatch = inboxMatch; trashMatch.id = "local-trash"; trashMatch.labels = ["TRASH"]
        var archivedMatch = inboxMatch; archivedMatch.id = "local-archive"; archivedMatch.labels = []
        searching.messages = [inboxMatch, trashMatch, archivedMatch]
        searching.search = "needle"
        check(Set(searching.visibleMessages.map(\.id)) == ["local-inbox", "local-trash", "local-archive"], "All-mail search includes archived and trashed downloaded messages")
        searching.searchScope = "folder"
        check(searching.visibleMessages.map(\.id) == ["local-inbox"], "Folder search excludes other sections")
        searching.search = "absent"
        check(searching.visibleMessages.isEmpty, "Changing search invalidates cached matches")
        searching.search = ""
        check(searching.visibleMessages.map(\.id) == ["local-inbox"], "Clearing search restores current folder")
        let searchConfig = URLSessionConfiguration.ephemeral; searchConfig.protocolClasses = [SearchMock.self]
        let searchClient = GmailClient(session: URLSession(configuration: searchConfig), client: .init(clientID: "test", clientSecret: "test"), token: .init(access: "test", refresh: "test", expiry: Date().addingTimeInterval(3600)), restore: false)
        let remoteSearching = MailStore(directory: directory.appendingPathComponent("RemoteSearch"), gmailClient: searchClient)
        remoteSearching.connected = true; remoteSearching.currentRemoteIDs = []
        remoteSearching.search = "attachment-only-match"
        await remoteSearching.fetchSearch()
        check(remoteSearching.visibleMessages.contains { $0.id == "remote-trash" }, "Server search includes Trash matches absent from the loaded inbox and local body")
        check(remoteSearching.searchNextPage == "more" && remoteSearching.nextPage == nil, "Search pagination stays separate from folder pagination")
        remoteSearching.searchScope = "folder"
        await remoteSearching.fetchSearch()
        check(remoteSearching.visibleMessages.map(\.id) == ["remote-inbox"], "Switching scope removes previous remote search results")
        remoteSearching.search = ""
        check(remoteSearching.visibleMessages.isEmpty, "Clearing remote search restores authoritative empty folder")
        let learningStore = MailStore(directory: directory.appendingPathComponent("Learning"))
        var confirmation = MailStore.samples()[0]
        confirmation.from = "Recruiting <jobs@example.com>"; confirmation.subject = "Application received for business analyst"
        confirmation.body = "Thank you for applying. Your application has been received and our recruiting team will review your profile. We will contact you about the next steps."; confirmation.labels = ["INBOX", "UNREAD"]
        var rejection = confirmation; rejection.subject = "Application outcome for business analyst"
        rejection.body = "Unfortunately we cannot proceed with your application. Other candidates more closely match this vacancy. We wish you success with your job search."
        var interview = confirmation; interview.subject = "Interview invitation for business analyst"
        interview.body = "We are pleased to invite you to an interview. Please choose a time for a meeting with the hiring manager and confirm your availability."
        var learner = LabelLearning()
        for index in 0..<3 {
            confirmation.id = "confirmation-\(index)"; learner.learn(confirmation, target: "confirmations")
            rejection.id = "rejection-\(index)"; learner.learn(rejection, target: "rejections")
            interview.id = "interview-\(index)"; learner.learn(interview, target: LabelLearning.primary)
        }
        confirmation.id = "new-confirmation"; rejection.id = "new-rejection"; interview.id = "new-interview"
        check(learner.prediction(confirmation, allowed: ["confirmations", "rejections"]) == "confirmations", "Matching confirmation content learns its own label")
        check(learner.prediction(rejection, allowed: ["confirmations", "rejections"]) == "rejections", "Same sender can map rejection content to a different label")
        check(learner.prediction(interview, allowed: ["confirmations", "rejections"]) == nil, "Learned Primary examples keep interview invitations in Inbox")
        var uncertain = confirmation; uncertain.subject = "New meeting details"; uncertain.body = "Please join us for a conversation tomorrow. What time works for you?"
        check(learner.prediction(uncertain, allowed: ["confirmations", "rejections"]) == nil, "Sender alone does not sort unfamiliar content")
        check(learner.prediction(confirmation, allowed: ["rejections"]) == nil, "Excluded label cannot be an automatic destination")
        var sparse = LabelLearning(); sparse.learn(confirmation, target: "confirmations"); sparse.learn(confirmation, target: "confirmations")
        check(sparse.examples.count == 1 && sparse.prediction(confirmation, allowed: ["confirmations"]) == nil, "Repeated moves of one message do not manufacture training evidence")
        var repeated = LabelLearning()
        for index in 0..<2 { var example = confirmation; example.id = "repeat-\(index)"; repeated.learn(example, target: "confirmations") }
        check(repeated.prediction(confirmation, allowed: ["confirmations"]) == "confirmations", "Two distinct matching sender corrections establish a content pattern")
        check(repeated.prediction(uncertain, allowed: ["confirmations"]) == nil, "Repeated sender still requires matching content")
        var ambiguous = learner
        for index in 0..<3 { var similar = confirmation; similar.id = "ambiguous-\(index)"; ambiguous.learn(similar, target: "rejections") }
        check(ambiguous.prediction(confirmation, allowed: ["confirmations", "rejections"]) == nil, "Conflicting label examples require manual handling")
        learningStore.labelLearning = learner; learningStore.messages = [confirmation, rejection, interview]
        learningStore.sortNewMail(learningStore.messages)
        check(learningStore.messages.first { $0.id == confirmation.id }!.labels == ["confirmations", "UNREAD"], "Automatic move archives a match and preserves unread state")
        check(learningStore.messages.first { $0.id == interview.id }!.labels.contains("INBOX"), "Uncertain or Primary predictions remain in Inbox")
        check(learningStore.labelLearning.examples.count == learner.examples.count, "Automatic decisions do not train themselves")
        let automated = learningStore.labelLearning.recentMoves.first { $0.messageID == confirmation.id }!
        if let i = learningStore.messages.firstIndex(where: { $0.id == confirmation.id }) { learningStore.messages[i].labels.insert("STARRED") }
        learningStore.undoAutomaticMove(automated)
        check(learningStore.messages.first { $0.id == confirmation.id }!.labels == ["INBOX", "UNREAD", "STARRED"], "Undo automatic move preserves later read and star changes")
        check(learningStore.labelLearning.examples.first { $0.id == confirmation.id }?.target == LabelLearning.primary, "Undo teaches that the automatic decision was incorrect")
        learningStore.persist(); learningStore.flushCache()
        let resumedLearning = MailStore(directory: learningStore.directory)
        check(resumedLearning.labelLearning.examples.count == learningStore.labelLearning.examples.count && resumedLearning.labelLearning.recentMoves.count == 1, "Learning and recent automatic moves survive restart")
        resumedLearning.resetLabelLearning()
        check(resumedLearning.labelLearning.examples.isEmpty && resumedLearning.messages.count == 3, "Reset learning leaves messages unchanged")
        learningStore.preferences.automaticLabeling = false; learningStore.messages = [confirmation]; learningStore.labelLearning = learner
        learningStore.sortNewMail([confirmation])
        check(learningStore.messages[0].labels.contains("INBOX"), "Disabling automatic moves keeps new matches in Inbox")
        learningStore.preferences.automaticLabeling = true
        learningStore.preferences.learnLabels = false
        learningStore.sortNewMail([confirmation])
        check(learningStore.messages[0].labels.contains("INBOX"), "Pausing learning also pauses automatic sorting")
        learningStore.preferences.learnLabels = true
        learningStore.labelLearning = LabelLearning()
        learningStore.select(confirmation.id)
        learningStore.actOnSelected(add: ["confirmations"], remove: ["INBOX"])
        check(learningStore.labelLearning.examples.first?.target == "confirmations", "Manual label action teaches its destination")
        learningStore.undo()
        check(learningStore.labelLearning.examples.count == 1 && learningStore.labelLearning.examples.first?.target == LabelLearning.primary, "Manual undo replaces the earlier example with a correction")
        var organized = confirmation; organized.id = "organized"; organized.labels = ["confirmations", "INBOX"]
        var multiLabel = confirmation; multiLabel.id = "multi-label"; multiLabel.labels = ["confirmations", "rejections"]
        learningStore.messages = [organized, multiLabel]; learningStore.preferences.primaryIncludedLabels = ["confirmations"]
        learningStore.resetLabelLearning(); learningStore.learnExistingLabels()
        check(learningStore.labelLearning.examples.first { $0.id == organized.id }?.target == "confirmations", "Import preserves a labeled example even when its label belongs in Primary")
        check(!learningStore.labelLearning.examples.contains { $0.id == multiLabel.id }, "Import skips ambiguous messages with multiple destinations")
        learningStore.labelLearning = learner
        var protected = confirmation; protected.labels = ["INBOX", "rejections"]
        learningStore.messages = [protected]; learningStore.sortNewMail([protected])
        check(learningStore.messages[0].labels == protected.labels, "Automatic sorting preserves messages already assigned a custom label")
        let store = MailStore(directory: directory)
        let searchIDs = store.visibleMessages.map(\.id)
        store.search = "Northpeak"
        check(store.visibleMessages.count == 1 && store.visibleMessages[0].senderName == "Northpeak", "Search filters the loaded list to matching emails")
        store.search = "no-such-phrase"
        check(store.visibleMessages.isEmpty, "Unmatched emails are hidden by local search")
        store.search = ""
        check(store.visibleMessages.map(\.id) == searchIDs, "Clearing search restores the loaded list")
        store.search = ""
        var legacyBody = store.messages[0]; legacyBody.html = ""
        legacyBody.attachments = [.init(id: "old-html", name: "Inline image", mimeType: "text/html", size: 12, data: Data("<p>Recovered</p>".utf8), contentID: "body")]
        legacyBody.recoverBodyParts()
        check(legacyBody.html == "<p>Recovered</p>" && legacyBody.attachments.isEmpty, "Cached LinkedIn body parts recover without a download")
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
        store.flushCache()
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
        var inlineReply = legacy
        inlineReply.quotedHTML = "<img width=\"14\" height=\"14\" src=\"data:image/png;base64,AQID\"><img src=\"data:image/png;base64,AQID\">"
        let inlinePackage = MIMEBuilder.inlineImages(inlineReply.quotedHTML!)
        check(inlinePackage.parts.count == 1 && inlinePackage.html.contains("width=\"14\"") && !inlinePackage.html.contains("data:image"), "Quoted images keep dimensions and share one inline MIME part")
        let inlineMIME = String(data: try MIMEBuilder.build(inlineReply, from: "sender@example.com"), encoding: .utf8)!
        check(inlineMIME.contains("multipart/related") && inlineMIME.contains("Content-Disposition: inline") && inlineMIME.contains("Content-ID: <image-"), "Quoted images send as related inline media rather than standalone attachments")

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
        threadStore.flushCache()
        let darkStore = MailStore(directory: directory.appendingPathComponent("threads"))
        check(darkStore.preferences.appearance == "dark", "Appearance choice persists")
        let primaryStore = MailStore(directory: directory.appendingPathComponent("primary-labels"))
        var labeled = primaryStore.messages[0]; labeled.labels = ["INBOX", "confirmations"]
        check(!primaryStore.contains(primaryStore.folders[0], labeled), "Confirmations excluded from Primary by default")
        primaryStore.setPrimaryLabel("confirmations", included: true)
        check(primaryStore.contains(primaryStore.folders[0], labeled), "Enabled label included in Primary")
        labeled.labels.insert("rejections")
        check(!primaryStore.contains(primaryStore.folders[0], labeled), "Any excluded label keeps mail out of Primary")
        primaryStore.setPrimaryLabel("rejections", included: true)
        check(primaryStore.contains(primaryStore.folders[0], labeled), "Multiple enabled labels allowed in Primary")
        primaryStore.folders.append(.init(id: "new-label", name: "New label", icon: "tag", query: "label:\"New label\"", isCustom: true))
        labeled.labels = ["INBOX", "new-label"]
        check(!primaryStore.contains(primaryStore.folders[0], labeled), "New labels excluded by default")
        check(primaryStore.primaryQuery.contains("-in:trash") && primaryStore.primaryQuery.contains("-in:spam"), "Primary server query excludes the same Spam and Trash messages as its list")
        check(primaryStore.primaryQuery.contains("-label:\"New label\""), "Remote query excludes newly discovered label")
        labeled.labels = ["INBOX", "CATEGORY_UPDATES"]
        check(primaryStore.contains(primaryStore.folders[0], labeled), "Unlabeled Updates remain in wide Primary")
        primaryStore.persist(); primaryStore.flushCache()
        let primaryReload = MailStore(directory: directory.appendingPathComponent("primary-labels"))
        check(primaryReload.primaryIncludedLabels == ["confirmations", "rejections"], "Primary label choices persist")
        let advanceStore = MailStore(directory: directory.appendingPathComponent("direction"))
        advanceStore.preferences.markRead = false
        let base = advanceStore.messages[0]
        advanceStore.messages = (0..<4).map { i in var m = base; m.id = "nav-\(i)"; m.threadID = m.id; m.date = Date().addingTimeInterval(Double(-i)); m.labels = ["INBOX"]; return m }
        let originals = advanceStore.messages
        advanceStore.select("nav-0"); advanceStore.navigate(1)
        advanceStore.perform("archive")
        check(advanceStore.selectedID == "nav-2", "Archive advances downward after downward navigation")
        advanceStore.messages = originals
        advanceStore.select("nav-3"); advanceStore.navigate(-1)
        advanceStore.perform("trash")
        check(advanceStore.selectedID == "nav-1", "Trash advances upward after upward navigation")
        advanceStore.perform("archive")
        check(advanceStore.selectedID == "nav-0", "Repeated removal preserves upward direction")
        advanceStore.perform("archive")
        check(advanceStore.selectedID == "nav-3", "List boundary falls back to surviving neighbor")
        advanceStore.perform("archive")
        check(advanceStore.selectedID == nil, "Removing last message clears selection")
        advanceStore.messages = originals; advanceStore.chooseFolder("primary"); advanceStore.select("nav-1")
        advanceStore.actOnSelected(add: ["rejections"], remove: [])
        check(advanceStore.selectedID == "nav-2", "Excluded label advances when message leaves Primary")
        primaryStore.setSidebarLabel("confirmations", visible: false)
        check(!primaryStore.sidebarLabels.contains { $0.id == "confirmations" }, "Hidden labels excluded from sidebar")
        check(primaryStore.folders.contains { $0.id == "confirmations" }, "Hiding label preserves underlying folder")
        check(primaryStore.sidebarFilters.contains { $0.id == "STARRED" } && !primaryStore.sidebarLabels.contains { $0.id == "STARRED" }, "System filters separated from labels")
        primaryStore.setSidebarLabel("confirmations", visible: true)
        check(primaryStore.sidebarLabels.contains { $0.id == "confirmations" }, "Hidden label can be restored")
        let dragStore = MailStore(directory: directory.appendingPathComponent("drag"))
        dragStore.preferences.markRead = false
        check(dragStore.reorderSidebarLabel("rejections", before: "confirmations"), "Sidebar reorder accepts custom labels")
        check(dragStore.sidebarLabels.firstIndex { $0.id == "rejections" }! < dragStore.sidebarLabels.firstIndex { $0.id == "confirmations" }!, "Sidebar respects saved label order")
        check(!dragStore.reorderSidebarLabel("primary", before: "rejections"), "Primary stays pinned first")
        var dragged = dragStore.messages[0]; dragged.labels = ["INBOX"]; dragStore.messages = [dragged]; dragStore.select(dragged.id)
        check(dragStore.handleSidebarDrop([dragStore.messageDragPayload(dragged.id)], target: "rejections"), "Message drop accepted on label")
        check(dragStore.messages[0].labels == ["rejections"], "Inbox drop files message under label")
        dragStore.chooseFolder("rejections"); dragStore.select(dragged.id)
        check(dragStore.handleSidebarDrop([dragStore.messageDragPayload(dragged.id)], target: "primary"), "Label drop accepted on Primary")
        check(dragStore.messages[0].labels == ["INBOX"], "Drop back to Primary removes source label")
        dragStore.chooseFolder("primary"); dragStore.select(dragged.id)
        check(dragStore.handleSidebarDrop([dragStore.messageDragPayload(dragged.id)], target: "TRASH"), "Drop to Trash accepted")
        check(dragStore.messages[0].labels == ["TRASH"], "Drop to Trash removes Inbox")
        dragStore.undo()
        check(dragStore.messages[0].labels == ["INBOX"], "Drag move supports Undo")
        check(!dragStore.handleSidebarDrop(["unrelated text"], target: "primary"), "External text cannot move mail")
        let settingsStore = MailStore(directory: directory.appendingPathComponent("settings"))
        let filterStore = MailStore(directory: directory.appendingPathComponent("unread-filter"))
        filterStore.toggleUnreadFilter()
        check(filterStore.unreadOnly && filterStore.visibleMessages.allSatisfy(\.unread), "Unread filter hides read messages")
        check(filterStore.activeFolderQuery.hasSuffix(" is:unread"), "Unread query searches beyond the loaded page")
        filterStore.chooseFolder("rejections")
        check(!filterStore.unreadOnly, "Unread filter does not affect another label")
        filterStore.chooseFolder("primary")
        check(filterStore.unreadOnly, "Each label retains its unread filter")
        filterStore.toggleUnreadFilter()
        check(!filterStore.unreadOnly, "Unread filter can return to all messages")

        settingsStore.preferences.markRead = false
        settingsStore.preferences.groupConversations = false
        settingsStore.messages = [incoming, outgoing]; settingsStore.select(incoming.id)
        check(settingsStore.threadMessages.map(\.id) == [incoming.id], "Ungrouped reading displays only selected message")
        settingsStore.preferences.groupConversations = true
        check(settingsStore.threadMessages.count == 2, "Grouping can be restored without losing conversation")
        settingsStore.messages[0].labels.insert("UNREAD"); settingsStore.messages[1].labels.insert("UNREAD")
        settingsStore.preferences.markRead = true; settingsStore.preferences.readDelay = 1
        settingsStore.select(incoming.id)
        check(settingsStore.messages[0].unread, "Delayed read does not mark immediately")
        settingsStore.select(nil)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        check(settingsStore.messages[0].unread, "Leaving message cancels read timer")
        settingsStore.select(incoming.id)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        check(settingsStore.messages.allSatisfy { !$0.unread }, "Read delay marks opened conversation after elapsed time")
        settingsStore.preferences.markRead = false
        settingsStore.preferences.hiddenSidebarLabels = ["rejections"]
        check(settingsStore.reorderSidebarLabel("rejections", before: "Newsletters", after: true) == false, "Unknown reorder targets are rejected")
        check(settingsStore.reorderSidebarLabel("rejections", before: "confirmations", after: true), "Hidden labels can be reordered in settings")
        check(settingsStore.orderedSidebarLabels.firstIndex { $0.id == "rejections" }! > settingsStore.orderedSidebarLabels.firstIndex { $0.id == "confirmations" }!, "Reorder supports insertion after target")
        check(settingsStore.setLabelShortcut("primary", value: Shortcut(key: "0", command: true)), "Label shortcut accepts free Command key")
        check(!settingsStore.setLabelShortcut("primary", value: Shortcut(key: "v", command: true)), "Label shortcut reserves paste")
        var notification = settingsStore.messages[0]; notification.labels = ["UNREAD", "confirmations"]
        settingsStore.preferences.notificationScope = "labels"; settingsStore.preferences.notificationLabels = ["confirmations"]
        check(settingsStore.notificationMatches(notification), "Selected-label notification scope matches")
        notification.labels = ["UNREAD", "rejections"]
        check(!settingsStore.notificationMatches(notification), "Notification excludes unselected labels")
        notification.labels = ["UNREAD", "confirmations"]
        settingsStore.preferences.notificationSenders = "other@example.com"
        check(!settingsStore.notificationMatches(notification), "Sender allowlist excludes other senders")
        settingsStore.preferences.notificationSenders = MailMessage.address(notification.from)
        check(settingsStore.notificationMatches(notification), "Sender allowlist accepts matching address")
        settingsStore.preferences.quietHours = true; settingsStore.preferences.quietStart = 22; settingsStore.preferences.quietEnd = 8
        let midnight = Calendar.current.startOfDay(for: Date())
        check(!settingsStore.notificationMatches(notification, now: midnight), "Quiet hours span midnight")
        check(settingsStore.notificationMatches(notification, now: midnight.addingTimeInterval(12 * 3600)), "Quiet hours allow midday")
        var queued = ComposeDraft(to: "recipient@example.com", subject: "Later", body: "Scheduled content")
        check(settingsStore.queueSend(queued, at: Date().addingTimeInterval(3600)), "Future send is queued")
        settingsStore.flushCache()
        let restored = MailStore(directory: settingsStore.directory)
        check(restored.drafts.first { $0.id == queued.id }?.scheduledAt != nil, "Scheduled delivery survives reopening")
        settingsStore.cancelScheduled(queued.id)
        check(settingsStore.drafts.first { $0.id == queued.id }?.scheduledAt == nil, "Schedule can be canceled without deleting draft")
        check(!settingsStore.queueSend(queued, at: Date().addingTimeInterval(-1)), "Past schedules are rejected")
        check(settingsStore.queueSend(queued, at: Date().addingTimeInterval(30), kind: "undo"), "Undo delay queues a message")
        settingsStore.undoSend()
        check(settingsStore.compose?.id == queued.id && settingsStore.undoSendID == nil && settingsStore.drafts.first { $0.id == queued.id }?.scheduledAt == nil, "Undo Send restores composer and cancels delivery")
        let fontText = NSAttributedString(string: "Formatted text", attributes: [.font: NSFont(name: "Georgia", size: 18)!, .foregroundColor: NSColor.systemBlue, .underlineStyle: 1])
        queued.richBody = try fontText.data(from: NSRange(location: 0, length: fontText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        queued.body = fontText.string
        let richMIME = String(data: try MIMEBuilder.build(queued, from: "sender@example.com"), encoding: .utf8)!
        check(richMIME.contains("multipart/alternative") && richMIME.contains("Content-Type: text/html"), "Formatted composer sends both plain and HTML alternatives")
        let retainedDraft = settingsStore.drafts.count
        settingsStore.clearDownloadedMedia()
        check(settingsStore.drafts.count == retainedDraft && !settingsStore.messages.isEmpty, "Cache clearing preserves drafts and messages")
        settingsStore.preferences.cacheMode = "fast"
        settingsStore.messages[0].attachments = [.init(id: "cached-file", name: "report.pdf", mimeType: "application/pdf", size: 5, data: Data("bytes".utf8))]
        settingsStore.persist(); settingsStore.flushCache()
        let external = MailStore(directory: settingsStore.directory)
        check(external.messages.first { $0.id == settingsStore.messages[0].id }?.attachments.first?.data == Data("bytes".utf8), "Faster cache restores attachment bytes from disk")
        let metadata = try JSONDecoder().decode(MailCache.self, from: Data(contentsOf: settingsStore.directory.appendingPathComponent("mail-cache.json")))
        check(metadata.messages.first { $0.id == settingsStore.messages[0].id }?.attachments.first?.data == nil && metadata.messages.first { $0.id == settingsStore.messages[0].id }?.attachments.first?.cachedFile != nil, "Faster cache avoids rewriting attachment bytes inside metadata")
        check(!settingsStore.setShortcut("compose", value: Shortcut(key: "0", command: true)), "Action shortcuts cannot conflict with label shortcuts")
        let emptyReply = ComposeDraft(to: "recipient@example.com", subject: "Reply")
        var styledEmpty = emptyReply; styledEmpty.richBody = Data("empty styling".utf8)
        check(!styledEmpty.hasUserChanges(from: emptyReply), "Formatting an empty reply does not create a draft")
        let deliveryConfig = URLSessionConfiguration.ephemeral; deliveryConfig.protocolClasses = [DeliveryMock.self]
        let fakeGmail = GmailClient(session: URLSession(configuration: deliveryConfig), client: .init(clientID: "test.apps.googleusercontent.com", clientSecret: "test"), token: .init(access: "test-access", refresh: "test-refresh", expiry: Date().addingTimeInterval(3600)), restore: false)
        let delivery = MailStore(directory: directory.appendingPathComponent("delivery"), gmailClient: fakeGmail)
        delivery.connected = true
        let scheduled = ComposeDraft(to: "recipient@example.com", subject: "Scheduled", body: "Test content")
        check(delivery.queueSend(scheduled, at: Date().addingTimeInterval(10)), "Delivery queue accepts connected mail")
        await delivery.processScheduled(now: Date().addingTimeInterval(20))
        check(DeliveryMock.sends == 1 && !delivery.drafts.contains { $0.id == scheduled.id }, "Due delivery sends once and removes queued draft")
        await delivery.processScheduled(now: Date().addingTimeInterval(30))
        check(DeliveryMock.sends == 1, "Completed schedule cannot send twice")
        DeliveryMock.fail = true
        let failing = ComposeDraft(to: "recipient@example.com", subject: "Failure", body: "Test content")
        _ = delivery.queueSend(failing, at: Date().addingTimeInterval(10))
        await delivery.processScheduled(now: Date().addingTimeInterval(20))
        check(delivery.drafts.first { $0.id == failing.id }?.deliveryState == "uncertain", "Unconfirmed delivery is preserved for manual review")
        let attempts = DeliveryMock.sends
        await delivery.processScheduled(now: Date().addingTimeInterval(30))
        check(DeliveryMock.sends == attempts, "Unconfirmed delivery is never retried automatically")
        print("PASS: \(checks) behavioral checks")
    }
}
