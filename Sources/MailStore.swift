import Foundation
import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

@MainActor
final class MailStore: ObservableObject {
    @Published var messages: [MailMessage] = []
    @Published var folders: [MailFolder] = MailFolder.defaults
    @Published var drafts: [ComposeDraft] = []
    @Published var folderID = "primary"
    @Published var selectedID: String?
    @Published var bulkIDs: Set<String> = []
    @Published var bulkMode = false
    var selectionAnchor: String?
    var rangeBase: Set<String>?
    @Published var conversation: [MailMessage] = []
    @Published var search = ""
    @Published var busy = false
    @Published var manualRefreshing = false
    @Published var error: String?
    @Published var status = "Preview mail"
    @Published var connected = false
    @Published var hasClient = false
    @Published var showSettings = false
    @Published var showLabels = false
    @Published var draftToDelete: ComposeDraft?
    @Published var draftsToDelete: [ComposeDraft] = []
    @Published var composerDismissRequest = 0
    @Published var selectedDraftID: String?
    var discardedDraftIDs: Set<String> = []
    @Published var compose: ComposeDraft?
    @Published var lastSync: Date?
    @Published var preferences = MailPreferences() { didSet { persist() } }
    @Published var account = GmailClient.sampleAccount
    @Published var focusSearch = false
    @Published var recordingShortcut: String?
    @Published var nextPage: String?
    var pending: [PendingChange] = []
    var currentRemoteIDs: Set<String>?
    var lastUndo: [(String, Set<String>)]?
    let demoMode: Bool
    let gmail: GmailClient
    let directory: URL
    var loadTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var selectionTask: Task<Void, Never>?
    var refreshGeneration = UUID()
    var historyID: String?
    private var flushing = false
    private var loadingCache = true
    private let cacheWriter = DispatchQueue(label: "Post.cache", qos: .utility)
    private var cacheWork: DispatchWorkItem?
    private var threadFetched: [String: Date] = [:]
    var selected: MailMessage? { guard !bulkMode else { return nil }; return messages.first { $0.id == selectedID } }
    var threadMessages: [MailMessage] {
        guard let selected else { return [] }
        let values = messages.filter { $0.threadID == selected.threadID }
        return (values.isEmpty ? [selected] : values).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    var folder: MailFolder { folders.first { $0.id == folderID } ?? MailFolder.defaults[0] }
    var primaryQuery: String { (preferences.primaryMode ?? "wide") == "wide" ? "in:inbox -category:promotions -label:newsletters" : "in:inbox category:primary" }
    func contains(_ folder: MailFolder, _ message: MailMessage) -> Bool {
        if message.labels.contains("TRASH") && folder.id != "TRASH" { return false }
        if message.labels.contains("SPAM") && folder.id != "SPAM" { return false }
        if folder.id == "primary", (preferences.primaryMode ?? "wide") == "wide" {
            let newsletterIDs = Set(folders.filter { $0.name.lowercased() == "newsletters" }.map(\.id))
            return message.labels.contains("INBOX") && !message.labels.contains("CATEGORY_PROMOTIONS") && message.labels.isDisjoint(with: newsletterIDs)
        }
        return folder.contains(message)
    }
    var visibleMessages: [MailMessage] {
        let values = messages.filter { message in
            if let remote = currentRemoteIDs, connected {
                guard remote.contains(message.id) else { return false }
                return contains(folder, message)
            }
            guard contains(folder, message) else { return false }
            return true
        }
        return values.sorted { $0.date > $1.date }
    }
    init(directory: URL? = nil) {
        self.demoMode = Bundle.main.bundleIdentifier == "com.jack.Post.demo"
        self.gmail = GmailClient(restore: !demoMode && directory == nil && ProcessInfo.processInfo.environment["POST_DATA_DIRECTORY"] == nil)
        let configured = ProcessInfo.processInfo.environment["POST_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.directory = demoMode ? FileManager.default.temporaryDirectory.appendingPathComponent("Post-Demo", isDirectory: true) : directory ?? configured ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Post", isDirectory: true)
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("mail-cache.json")), let cache = try? JSONDecoder().decode(MailCache.self, from: data) {
            messages = cache.messages; folders = cache.folders.isEmpty ? MailFolder.defaults : cache.folders; drafts = cache.drafts; pending = cache.pending; lastSync = cache.lastSync; preferences = cache.preferences; historyID = cache.historyID; account = cache.account ?? GmailClient.sampleAccount
        } else { messages = Self.samples() }
        if demoMode {
            messages = Self.samples(); folders = MailFolder.defaults; drafts = []; pending = []; historyID = nil; account = GmailClient.sampleAccount
            preferences = MailPreferences(); preferences.markRead = false
            var earlier = messages[0]; earlier.id = "demo-thread-1"; earlier.date = Date().addingTimeInterval(-86400); earlier.subject = "Business Analyst interview"; earlier.body = "Hi Alex,\n\nThanks for applying. We'd like to arrange an interview next week. Which days work for you?\n\nBest,\nJordan"; earlier.labels = ["confirmations"]
            var reply = earlier; reply.id = "demo-thread-2"; reply.from = "Alex <alex@example.com>"; reply.to = "Jordan <team@northpeak.example>"; reply.date = Date().addingTimeInterval(-72000); reply.body = "Hi Jordan,\n\nThursday morning works for me. Thanks for the invitation.\n\nBest,\nAlex"; reply.labels = ["SENT"]
            messages += [earlier, reply]
        }
        for i in messages.indices { messages[i].recoverBodyParts() }
        loadingCache = false
        if !connected { updateLocalCounts() }
    }
    func start() {
        if demoMode { status = "Demo • fictional mail • local changes only"; return }
        Task {
            let state = await gmail.connectionState(); hasClient = state.0; connected = state.1
            if connected { do { account = try await gmail.accountAddress(); await refresh() } catch { status = "Gmail connection needs attention"; self.error = error.localizedDescription } }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.connected && !self.busy { await self.refresh(silent: true) }
            }
        }
    }
    func persist() {
        guard !loadingCache else { return }
        let cache = MailCache(messages: messages, folders: folders, drafts: drafts, pending: pending, lastSync: lastSync, account: connected ? account : nil, historyID: historyID, preferences: preferences)
        let directory = directory
        cacheWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(cache)
                try data.write(to: directory.appendingPathComponent("mail-cache.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch { Task { @MainActor [weak self] in self?.error = "Post could not save its local cache. \(error.localizedDescription)" } }
        }
        cacheWork = work
        cacheWriter.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func flushCache() {
        guard let cacheWork else { return }
        cacheWork.cancel()
        // Persist an immediate snapshot, then wait for earlier writes before quitting.
        let cache = MailCache(messages: messages, folders: folders, drafts: drafts, pending: pending, lastSync: lastSync, account: connected ? account : nil, historyID: historyID, preferences: preferences)
        let directory = directory
        cacheWriter.sync {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(cache) { try? data.write(to: directory.appendingPathComponent("mail-cache.json"), options: [.atomic, .completeFileProtectionUnlessOpen]) }
        }
    }
    func updateLocalCounts() {
        for i in folders.indices {
            let f = folders[i]
            let group = messages.filter { contains(f, $0) }
            folders[i].totalCount = group.count; folders[i].unreadCount = group.filter(\.unread).count
            if f.id == "DRAFT" { folders[i].totalCount = drafts.count; folders[i].unreadCount = 0 }
        }
    }
    func chooseFolder(_ id: String) {
        folderID = id; selectedDraftID = nil; bulkIDs = []; bulkMode = false; selectionAnchor = nil; rangeBase = nil; selectedID = nil; conversation = []; search = ""; currentRemoteIDs = nil; nextPage = nil
        if connected { scheduleLoad() }
    }
    func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task { try? await Task.sleep(nanoseconds: 300_000_000); if !Task.isCancelled { await refresh() } }
    }
    func select(_ id: String?) {
        bulkIDs = []; bulkMode = false; selectionAnchor = id; rangeBase = nil
        selectedDraftID = folderID == "DRAFT" ? id : nil
        selectedID = id; conversation = []; selectionTask?.cancel()
        guard let id, let message = messages.first(where: { $0.id == id }) else { return }
        conversation = messages.filter { $0.threadID == message.threadID }.sorted { $0.date < $1.date }
        if preferences.markRead && message.unread { change(id, add: [], remove: ["UNREAD"], recordUndo: false) }
        if connected, threadFetched[message.threadID].map({ Date().timeIntervalSince($0) < 120 }) != true {
            selectionTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                    try Task.checkCancellation()
                    let values = try await gmail.thread(message.threadID, cached: messages)
                    guard !Task.isCancelled, selectedID == id else { return }
                    threadFetched[message.threadID] = Date()
                    merge(values); conversation = messages.filter { $0.threadID == message.threadID }.sorted { $0.date < $1.date }; persist()
                    if preferences.markRead { for m in values where m.unread { change(m.id, add: [], remove: ["UNREAD"], recordUndo: false) } }
                } catch { if !Task.isCancelled { status = "Showing cached message" } }
            }
        }
    }
    var selectionList: [String] { folderID == "DRAFT" ? drafts.map(\.id) : visibleMessages.map(\.id) }
    var selectionCursor: String? { folderID == "DRAFT" ? (selectedDraftID ?? selectedID) : selectedID }
    var actionIDs: Set<String> { bulkMode ? bulkIDs : Set(selectionCursor.map { [$0] } ?? []) }
    func clickMessage(_ id: String, shift: Bool = false, command: Bool = false) {
        guard selectionList.contains(id) else { return }
        if shift { extendSelection(to: id); return }
        if command {
            let initial = actionIDs
            bulkMode = true; bulkIDs = initial
            if !bulkIDs.insert(id).inserted { bulkIDs.remove(id) }
            selectedID = bulkIDs.contains(id) ? id : selectionList.last(where: { bulkIDs.contains($0) })
            selectedDraftID = nil
            selectionAnchor = selectedID; rangeBase = nil; conversation = []; selectionTask?.cancel()
            if bulkIDs.isEmpty { select(nil) }
        } else { select(id) }
    }
    func extendSelection(to id: String) {
        let list = selectionList
        guard let end = list.firstIndex(of: id) else { return }
        let anchor = selectionAnchor ?? selectionCursor ?? id
        let start = list.firstIndex(of: anchor) ?? end
        if rangeBase == nil { rangeBase = bulkMode ? bulkIDs : [] }
        bulkIDs = (rangeBase ?? []).union(list[min(start, end)...max(start, end)])
        selectionAnchor = anchor; selectedID = id; selectedDraftID = nil; bulkMode = true
        conversation = []; selectionTask?.cancel()
    }
    func extendNavigation(_ direction: Int) {
        let list = selectionList
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0 == selectionCursor }
        let next = index.map { min(max($0 + direction, 0), list.count - 1) } ?? (direction < 0 ? list.count - 1 : 0)
        extendSelection(to: list[next])
    }
    func reconcileBulkSelection() {
        guard bulkMode else { return }
        bulkIDs.formIntersection(selectionList)
        if bulkIDs.isEmpty { select(nil) }
        else if !bulkIDs.contains(selectedID ?? "") { selectedID = selectionList.first { bulkIDs.contains($0) }; selectionAnchor = selectedID; rangeBase = nil }
    }
    func prepareContextSelection(_ id: String) {
        if !actionIDs.contains(id) { select(id) }
    }
    func navigate(_ direction: Int) {
        if folderID == "DRAFT" {
            let list = selectionList
            guard !list.isEmpty else { return }
            let index = list.firstIndex { $0 == selectionCursor }
            let next = index.map { min(max($0 + direction, 0), list.count - 1) } ?? (direction < 0 ? list.count - 1 : 0)
            select(list[next]); return
        }
        let list = visibleMessages
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID }
        let next = index.map { min(max($0 + direction, 0), list.count - 1) } ?? (direction < 0 ? list.count - 1 : 0)
        select(list[next].id)
    }
    func merge(_ incoming: [MailMessage]) {
        var map = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for m in incoming {
            var value = m
            value.recoverBodyParts()
            value.resolveInlineImages(reusing: map[m.id])
            for change in pending where change.messageID == value.id { value.labels.formUnion(change.add); value.labels.subtract(change.remove) }
            map[m.id] = value
        }
        messages = Array(map.values).sorted { $0.date > $1.date }
    }
    func refresh(silent: Bool = false, more: Bool = false, manual: Bool = false) async {
        guard connected else { updateLocalCounts(); status = "Preview mail • changes stay on this Mac"; return }
        guard !busy else { return }
        busy = true; manualRefreshing = manual
        defer { busy = false; manualRefreshing = false }
        let generation = UUID(); refreshGeneration = generation
        var historyValid = historyID != nil
        let oldIDs = Set(messages.map(\.id)); let viewID = folderID
        if !silent { status = "Syncing Gmail…" }
        do {
            try await flushPending()
            if !more {
                if let historyID {
                    do {
                        let (updates, deleted, newest) = try await gmail.changes(since: historyID, cachedIDs: Set(messages.map(\.id)))
                        for message in updates { threadFetched.removeValue(forKey: message.threadID) }
                        merge(updates); messages.removeAll { deleted.contains($0.id) }; self.historyID = newest
                    } catch MailError.http(404, _) { self.historyID = nil; historyValid = false }
                }
                if self.historyID == nil { self.historyID = try await gmail.profileHistory() }
            }
            let query = folderID == "primary" ? primaryQuery : folder.query
            let page = more ? nextPage : nil
            let (incoming, pageToken) = try await gmail.list(query: query, page: page, cached: historyValid ? messages : [])
            guard !Task.isCancelled, folderID == viewID, refreshGeneration == generation else { return }
            merge(incoming)
            currentRemoteIDs = more ? (currentRemoteIDs ?? []).union(incoming.map(\.id)) : Set(incoming.map(\.id))
            nextPage = pageToken
            if !more {
                let remoteFolders = try await gmail.folders()
                guard folderID == viewID else { return }
                folders = remoteFolders
                if !folders.contains(where: { $0.id == folderID }) { folderID = "primary"; currentRemoteIDs = nil }
                // Composite views count messages in their own query, rather than a category's archived mail.
                let primaryUnread = try await gmail.count(query: primaryQuery + " is:unread")
                let primaryTotal = preferences.totalCounts ? try await gmail.count(query: primaryQuery) : folders.first(where: { $0.id == "primary" })?.totalCount ?? 0
                if let i = folders.firstIndex(where: { $0.id == "primary" }) { folders[i].unreadCount = primaryUnread; folders[i].totalCount = primaryTotal }
                if let i = folders.firstIndex(where: { $0.id == "all" }) {
                    folders[i].unreadCount = try await gmail.count(query: "-in:trash -in:spam -in:drafts is:unread")
                    if preferences.totalCounts { folders[i].totalCount = try await gmail.count(query: "-in:trash -in:spam -in:drafts") }
                }
                if folderID == "DRAFT" { await loadDrafts() }
            }
            if silent && preferences.notifications {
                let new = incoming.filter { !oldIDs.contains($0.id) && $0.unread && $0.labels.contains("INBOX") }
                if let first = new.first { notify(first, count: new.count) }
            }
            lastSync = Date(); status = "Gmail is up to date"; persist()
        } catch {
            if !Task.isCancelled {
                if case MailError.rateLimited = error { status = error.localizedDescription }
                else { status = "Offline or sync unavailable • cached mail is available"; if !silent { self.error = error.localizedDescription } }
            }
        }
    }
    func flushPending() async throws {
        guard !flushing else { return }
        flushing = true; defer { flushing = false }
        while let first = pending.first {
            try await gmail.modify(first); pending.removeFirst(); persist()
        }
    }
    func change(_ id: String, add: [String], remove: [String], recordUndo: Bool = true) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let old = messages[index].labels
        if recordUndo { lastUndo = [(id, old)] }
        messages[index].labels.formUnion(add); messages[index].labels.subtract(remove)
        let changed = messages[index]
        conversation = conversation.map { $0.id == id ? changed : $0 }
        if connected {
            for i in folders.indices {
                let previous = MailMessage(id: changed.id, threadID: changed.threadID, from: changed.from, to: changed.to, subject: changed.subject, snippet: changed.snippet, body: changed.body, date: changed.date, labels: old)
                let was = contains(folders[i], previous); let now = contains(folders[i], changed)
                folders[i].totalCount = max(0, folders[i].totalCount + (now ? 1 : 0) - (was ? 1 : 0))
                folders[i].unreadCount = max(0, folders[i].unreadCount + (now && changed.unread ? 1 : 0) - (was && previous.unread ? 1 : 0))
            }
            if !contains(folder, changed) { currentRemoteIDs?.remove(id) }
            pending.append(.init(messageID: id, add: add, remove: remove))
            Task {
                do { try await flushPending(); status = "Saved to Gmail" }
                catch { status = "Change queued • it will retry on refresh"; self.error = error.localizedDescription }
            }
        } else { updateLocalCounts(); status = "Preview change saved locally" }
        persist()
    }
    func actOnSelected(add: [String], remove: [String], advance: Bool = false) {
        let ids = actionIDs
        guard !ids.isEmpty else { return }
        let wasBulk = bulkMode
        let before = visibleMessages
        let index = before.firstIndex { ids.contains($0.id) } ?? 0
        let snapshots = messages.filter { ids.contains($0.id) }.map { ($0.id, $0.labels) }
        for message in before where ids.contains(message.id) { change(message.id, add: add, remove: remove, recordUndo: false) }
        lastUndo = snapshots
        if wasBulk {
            let remaining = Set(visibleMessages.map(\.id)).intersection(ids)
            bulkIDs = remaining; rangeBase = nil
            if remaining.isEmpty { select(nil) }
            else if !remaining.contains(selectedID ?? "") { selectedID = visibleMessages.first { remaining.contains($0.id) }?.id; selectionAnchor = selectedID }
        } else if advance { let list = visibleMessages; select(list.isEmpty ? nil : list[min(index, list.count - 1)].id) }
    }
    func moveSelectedToInbox() {
        actOnSelected(add: ["INBOX"], remove: ["TRASH", "SPAM"], advance: true)
    }
    func undo() {
        guard let snapshots = lastUndo else { return }
        for (id, labels) in snapshots {
            guard let message = messages.first(where: { $0.id == id }) else { continue }
            change(id, add: Array(labels.subtracting(message.labels)), remove: Array(message.labels.subtracting(labels)), recordUndo: false)
        }
        lastUndo = nil
    }
    func newCompose(kind: String = "new", replyingTo: MailMessage? = nil) {
        var draft = ComposeDraft()
        draft.body = preferences.signature.isEmpty ? "" : "\n\n" + preferences.signature
        if kind != "new", let message = replyingTo ?? selected {
            let reply: String
            if message.senderAddress.lowercased() == account.lowercased() {
                reply = message.to.split(separator: ",").map { MailMessage.address(String($0)) }.first { $0.lowercased() != account.lowercased() } ?? message.to
            } else { reply = message.replyTo.isEmpty ? message.senderAddress : MailMessage.address(message.replyTo) }
            draft.subject = message.subject.lowercased().hasPrefix(kind == "forward" ? "fwd:" : "re:") ? message.subject : (kind == "forward" ? "Fwd: " : "Re: ") + message.subject
            if kind != "forward" {
                draft.to = reply; draft.threadID = message.threadID; draft.inReplyTo = message.rfcMessageID; draft.references = message.references
                if kind == "replyAll" {
                    draft.cc = (message.to + "," + message.cc).split(separator: ",").map { MailMessage.address(String($0)) }.filter { !$0.isEmpty && $0.lowercased() != account.lowercased() && $0.lowercased() != reply.lowercased() }.joined(separator: ", ")
                }
            }
            draft.quoteHeading = "On \(message.date.formatted(date: .abbreviated, time: .shortened)), \(message.senderName) wrote:"
            draft.quotedText = message.body
            draft.quotedHTML = message.html.isEmpty ? nil : message.html
            if kind == "forward" { draft.attachments = message.attachments }
        }
        compose = draft
    }
    func saveDraft(_ draft: ComposeDraft, sync: Bool = true) {
        guard !discardedDraftIDs.contains(draft.id) else { return }
        var value = draft; value.updated = Date(); value.localChanges = true
        if value.gmailDraftID == nil { value.gmailDraftID = drafts.first { $0.id == draft.id }?.gmailDraftID }
        if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = value } else { drafts.append(value) }
        if !connected { updateLocalCounts() }
        persist(); status = "Draft saved on this Mac"
        if connected && sync && !value.to.isEmpty {
            Task {
                do {
                    var prepared = value
                    for i in prepared.attachments.indices where prepared.attachments[i].data == nil {
                        guard let sourceID = prepared.attachments[i].messageID else { throw MailError.message("Open the source message to download forwarded attachments.") }
                        prepared.attachments[i].data = try await gmail.attachment(messageID: sourceID, attachment: prepared.attachments[i])
                    }
                    guard !discardedDraftIDs.contains(value.id) else { return }
                    let id = try await gmail.saveDraft(prepared)
                    if discardedDraftIDs.contains(value.id) { try? await gmail.deleteDraft(id); return }
                    if let i = drafts.firstIndex(where: { $0.id == value.id }) { drafts[i].gmailDraftID = id; if drafts[i].updated == value.updated { drafts[i].localChanges = false } }
                    if compose?.id == value.id { compose?.gmailDraftID = id }
                    status = "Draft saved to Gmail"; persist()
                } catch { status = "Draft saved locally • Gmail sync pending" }
            }
        }
    }
    func deleteDraft(_ value: ComposeDraft) {
        discardedDraftIDs.insert(value.id)
        drafts.removeAll { $0.id == value.id }
        if selectedDraftID == value.id { selectedDraftID = nil }; bulkIDs.remove(value.id); if selectedID == value.id { selectedID = nil }; if bulkMode && bulkIDs.isEmpty { select(nil) }
        if compose?.id == value.id { compose = nil }
        updateLocalCounts(); persist()
        if connected, let id = value.gmailDraftID {
            Task {
                do { try await gmail.deleteDraft(id); status = "Draft deleted" }
                catch {
                    discardedDraftIDs.remove(value.id); drafts.append(value); updateLocalCounts(); persist()
                    self.error = "Gmail could not delete this draft. It has been restored. \(error.localizedDescription)"
                }
            }
        }
    }
    func loadDrafts() async {
        do {
            let remote = try await gmail.drafts().map { item in
                var item = item
                if let existing = drafts.first(where: { $0.gmailDraftID == item.gmailDraftID }) {
                    if existing.localChanges == true || selectedDraftID == existing.id { return existing }
                    item.id = existing.id
                    let full = existing.body + (existing.quotedText.map { "\n\n" + (existing.quoteHeading ?? "Previous message") + "\n" + $0 } ?? "")
                    if full == item.body { item.body = existing.body; item.quotedText = existing.quotedText; item.quotedHTML = existing.quotedHTML; item.quoteHeading = existing.quoteHeading }
                }
                item.separateLegacyQuote()
                return item
            }
            let unsynced = drafts.filter { $0.gmailDraftID == nil }
            drafts = remote + unsynced; persist()
        } catch { self.error = error.localizedDescription }
    }
    func send(_ value: ComposeDraft) async -> Bool {
        guard connected else { error = "Connect Gmail before sending. Your draft can be saved locally."; return false }
        do {
            var prepared = value
            for i in prepared.attachments.indices where prepared.attachments[i].data == nil {
                guard let sourceID = prepared.attachments[i].messageID else { throw MailError.message("The forwarded attachment is not downloaded.") }
                prepared.attachments[i].data = try await gmail.attachment(messageID: sourceID, attachment: prepared.attachments[i])
            }
            let sent = try await gmail.send(prepared)
            merge([sent]); discardedDraftIDs.insert(value.id); selectedDraftID = nil; drafts.removeAll { $0.id == value.id }
            if let id = value.gmailDraftID { try? await gmail.deleteDraft(id) }
            compose = nil; status = "Message sent"; persist(); return true
        } catch { self.error = "Sending was not confirmed. Check Sent before retrying. \(error.localizedDescription)"; saveDraft(value, sync: false); return false }
    }
    func importOAuth() {
        guard !demoMode else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await gmail.importClient(Data(contentsOf: url)); let state = await gmail.connectionState(); hasClient = state.0; connected = state.1; status = "Google client imported securely"; if connected { await refresh() } } catch { self.error = error.localizedDescription } }
    }
    func signIn() {
        guard !demoMode else { return }
        busy = true
        Task {
            do { account = try await gmail.signIn(); connected = true; messages = []; folders = MailFolder.defaults.filter { !$0.isCustom }; pending = []; currentRemoteIDs = nil; busy = false; await refresh() }
            catch { busy = false; self.error = error.localizedDescription }
        }
    }
    func disconnect() {
        Task { await gmail.disconnect(); connected = false; status = "Disconnected • cached mail remains on this Mac"; persist() }
    }
    func addLabel(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !folders.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        if connected {
            Task { do { let f = try await gmail.createLabel(clean); folders.insert(f, at: 1); persist() } catch { self.error = error.localizedDescription } }
        } else { folders.insert(.init(id: UUID().uuidString, name: clean, icon: "tag", query: "", isCustom: true), at: 1); persist() }
    }
    func download(_ attachment: MailAttachment, message: MailMessage) {
        Task {
            do {
                let data: Data
                if let cached = attachment.data { data = cached }
                else {
                    guard connected else { throw MailError.message("Connect Gmail to download this attachment.") }; data = try await gmail.attachment(messageID: message.id, attachment: attachment)
                    if let m = messages.firstIndex(where: { $0.id == message.id }), let a = messages[m].attachments.firstIndex(where: { $0.id == attachment.id }) { messages[m].attachments[a].data = data; persist() }
                }
                let panel = NSSavePanel(); panel.nameFieldStringValue = attachment.name
                if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
            } catch { self.error = error.localizedDescription }
        }
    }
    func setShortcut(_ action: String, value: Shortcut) -> Bool {
        if let conflict = preferences.shortcuts.first(where: { $0.key != action && $0.value == value }) {
            let name = Shortcut.names.first { $0.0 == conflict.key }?.1 ?? conflict.key
            error = "\(value.display) is already assigned to \(name). Choose another shortcut."; return false
        }
        preferences.shortcuts[action] = value; return true
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    private func notify(_ message: MailMessage, count: Int) {
        let c = UNMutableNotificationContent(); c.title = count > 1 ? "\(count) new messages" : message.senderName; c.body = message.subject
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: message.id, content: c, trigger: nil))
    }
    func perform(_ action: String) {
        switch action {
        case "reply", "replyAll": if selected != nil { newCompose(kind: action) }
        case "next": navigate(1)
        case "previous": navigate(-1)
        case "label": if !actionIDs.isEmpty { showLabels = true }
        case "trash": if folderID == "DRAFT" { draftsToDelete = drafts.filter { actionIDs.contains($0.id) }; return }; actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true)
        case "archive": actOnSelected(add: [], remove: ["INBOX"], advance: true)
        case "clear": selectedDraftID = nil; select(nil)
        case "compose": newCompose()
        case "search": focusSearch = true
        case "refresh": Task { await refresh(manual: true) }
        case "sidebar": preferences.collapsed.toggle()
        default: break
        }
    }
    static func samples() -> [MailMessage] {
        let data: [(String, String, String, Set<String>, Bool)] = [
            ("Northpeak", "Interview invitation: Business Analyst", "Hi Alex,\n\nWe would like to invite you to a conversation about the Business Analyst role.\n\nAre you available on Thursday at 11:00? The call will take about 45 minutes. We will discuss your experience and the projects you have worked on.\n\nPlease reply with your availability and we will send the meeting link.\n\nBest,\nAlex\nNorthpeak", ["INBOX", "CATEGORY_PERSONAL"], true),
            ("Cedar & Coast", "Your assessment schedule", "Hi Alex,\n\nThe next step is a short assessment. Please tell us which day works for you.\n\nKind regards,\nCedar & Coast", ["INBOX", "CATEGORY_PERSONAL"], true),
            ("Brightly", "A question about your application", "Hi Alex,\n\nCould you send us a little more detail about your project experience?\n\nThank you,\nThe Brightly team", ["INBOX", "CATEGORY_PERSONAL"], true),
            ("Foundry", "Next steps", "Hi Alex,\n\nWe have reviewed your application and would like to arrange a call. Please send us two available times.\n\nBest,\nThe Foundry team", ["INBOX", "CATEGORY_PERSONAL"], false),
            ("Willow Systems", "Additional information needed", "Hi Alex,\n\nPlease confirm when you would be available to start.\n\nThank you.", ["INBOX", "CATEGORY_PERSONAL"], true),
            ("Helios Health", "Application received", "Thank you for applying. We have received your application and will review it shortly.", ["confirmations"], true),
            ("Brightly", "Application outcome", "Thank you for your interest. We will not be moving forward with your application for this position.", ["rejections"], true),
            ("Daily Notes", "This week's reading", "A few articles you might enjoy this week.", ["newsletters"], true),
            ("Local Store", "Your weekly offers", "Browse this week's offers.", ["CATEGORY_PROMOTIONS"], true)
        ]
        return data.enumerated().map { i, item in
            var labels = item.3; if item.4 { labels.insert("UNREAD") }
            return MailMessage(id: "sample-\(i)", threadID: "sample-\(i)", from: "\(item.0) <team@\(item.0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: "")).example>", to: GmailClient.sampleAccount, subject: item.1, snippet: item.2.replacingOccurrences(of: "\n", with: " "), body: item.2, date: Date().addingTimeInterval(Double(-i * 3600)), labels: labels)
        }
    }
}
