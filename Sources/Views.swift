import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

typealias LocalState<Value> = SwiftUI.State<Value>

enum PostStyle {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let background = adaptive(NSColor(srgbRed: 0.965, green: 0.974, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1))
    static let sidebar = adaptive(NSColor(srgbRed: 0.935, green: 0.95, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1))
    static let surface = adaptive(.white, NSColor(srgbRed: 0.13, green: 0.16, blue: 0.20, alpha: 1))
    static let accent = adaptive(NSColor(srgbRed: 0.23, green: 0.43, blue: 0.64, alpha: 1), NSColor(srgbRed: 0.54, green: 0.73, blue: 0.94, alpha: 1))
    static let selection = adaptive(NSColor(srgbRed: 0.89, green: 0.94, blue: 0.995, alpha: 1), NSColor(srgbRed: 0.18, green: 0.28, blue: 0.39, alpha: 1))
    static let bulk = adaptive(NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.19, green: 0.23, blue: 0.29, alpha: 1))
    static let buttonText = adaptive(.white, NSColor(srgbRed: 0.07, green: 0.12, blue: 0.19, alpha: 1))
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let subtle = adaptive(NSColor(white: 0, alpha: 0.035), NSColor(white: 1, alpha: 0.055))
    static func scheme(_ preference: String?) -> ColorScheme? {
        preference == "dark" ? .dark : preference == "light" ? .light : nil
    }
}

struct MailWindow: View {
    @EnvironmentObject var store: MailStore
    @LocalState private var rowFrames: [String: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @LocalState private var newLabel = ""
    @LocalState private var showNewLabel = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                RefreshStrip(active: store.manualRefreshing).frame(height: 2)
                HStack(spacing: 0) {
                    messageList.frame(width: store.preferences.collapsed ? 370 : 330)
                    ZStack {
                        emptyReading.opacity(store.bulkMode ? 0 : 1).accessibilityHidden(store.bulkMode)
                        GeometryReader { geometry in
                            if store.folderID == "DRAFT", !store.bulkMode, let draft = store.drafts.first(where: { $0.id == store.selectedDraftID }) {
                                ComposePane(initial: draft, embedded: true).id(draft.id)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .background(PostStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .shadow(color: PostStyle.accent.opacity(0.1), radius: 20, x: 0, y: 8)
                                    .transition(.opacity)
                            } else if store.bulkMode {
                                BulkSelectionPane().frame(width: geometry.size.width, height: geometry.size.height).transition(.opacity)
                            } else if let message = store.selected {
                                let destination = geometry.frame(in: .named("mailWindow"))
                                let source = rowFrames[message.id] ?? destination
                                ReadingPane()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .background(PostStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .shadow(color: Color(red: 0.25, green: 0.35, blue: 0.45).opacity(0.12), radius: 20, x: 0, y: 8)
                                    .transition(reduceMotion ? .opacity : .modifier(
                                        active: CardFlight(x: source.midX - destination.midX, y: source.midY - destination.midY, sx: source.width / max(1, destination.width), sy: source.height / max(1, destination.height), opacity: 0),
                                        identity: CardFlight(x: 0, y: 0, sx: 1, sy: 1, opacity: 1)))
                            }
                        }.zIndex(1)
                    }.padding(.leading, 12).padding(.trailing, 22).padding(.bottom, 16)
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
                footer
            }
        }
        .coordinateSpace(name: "mailWindow")
        .onPreferenceChange(MessageFrames.self) { rowFrames = $0 }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChrome())
        .buttonStyle(PostButtonStyle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.preferences.collapsed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.selectedID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.selectedDraftID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bulkIDs)
        .background(PostStyle.background)
        .foregroundStyle(.primary)
        .tint(PostStyle.accent)
        .frame(minWidth: 980, minHeight: 630)
        .preferredColorScheme(PostStyle.scheme(store.preferences.appearance))
        .sheet(isPresented: $store.showSettings) { SettingsPane().environmentObject(store) }
        .sheet(item: $store.compose) { draft in ComposePane(initial: draft).environmentObject(store) }
        .sheet(isPresented: $store.showLabels) { LabelPicker().environmentObject(store) }
        .alert("Post", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("New label", isPresented: $showNewLabel) { TextField("Label name", text: $newLabel); Button("Create") { store.addLabel(newLabel); newLabel = "" }; Button("Cancel", role: .cancel) {} }
        .postPrompt("Delete drafts?", isPresented: Binding(get: { store.draftToDelete != nil || !store.draftsToDelete.isEmpty }, set: { if !$0 { store.draftToDelete = nil; store.draftsToDelete = [] } }), message: "This deletes the selected drafts from Post and Gmail if they have been synced.", actions: ["Delete", "Cancel"]) { response in
            if response == 0 {
                let targets = store.draftsToDelete.isEmpty ? store.draftToDelete.map { [$0] } ?? [] : store.draftsToDelete
                for draft in targets { store.deleteDraft(draft) }
            }
            store.draftToDelete = nil; store.draftsToDelete = []
        }
        .onChange(of: store.selectionList) { _, _ in store.reconcileBulkSelection() }
        .onChange(of: store.selectedDraftID) { _, _ in searchFocused = false }
        .onChange(of: store.selectedID) { _, _ in searchFocused = false }
        .onChange(of: store.focusSearch) { _, value in if value { searchFocused = true; store.focusSearch = false } }

    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Button { store.preferences.collapsed.toggle() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 16)).frame(width: 44, height: 38)
                }.buttonStyle(PostButtonStyle(inset: 0)).help(store.preferences.collapsed ? "Expand sidebar" : "Collapse sidebar")
                Text("Post").font(.system(size: 14, weight: .semibold)).foregroundStyle(PostStyle.secondary).offset(x: 218)
            }.frame(width: 264, height: 38, alignment: .leading).padding(.leading, 20).padding(.top, 43).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.folders) { folder in
                        if folder.id == "STARRED" { Color.clear.frame(height: 14) }
                        let count = store.preferences.totalCounts ? folder.totalCount : folder.unreadCount
                        let selected = store.folderID == folder.id
                        Button { NSApp.keyWindow?.makeFirstResponder(nil); store.chooseFolder(folder.id) } label: {
                            ZStack(alignment: .leading) {
                                Image(systemName: folder.icon.replacingOccurrences(of: "circle", with: "square"))
                                    .font(.system(size: 17, weight: .regular)).frame(width: 44, height: 44)
                                    .offset(x: store.preferences.collapsed ? 0 : 6)
                                Text(folder.name).font(.system(size: 13, weight: selected ? .medium : .regular))
                                    .lineLimit(1).frame(width: 166, alignment: .leading).offset(x: 58)
                                if count > 0 {
                                    Text(count > 9999 ? "9k+" : String(count)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                                        .foregroundStyle(selected ? PostStyle.accent : PostStyle.secondary)
                                        .frame(width: 25, alignment: .trailing).offset(x: 230)
                                }
                            }.frame(width: 264, height: 44, alignment: .leading)
                                .frame(width: store.preferences.collapsed ? 44 : 264, alignment: .leading).clipped()
                                .background(selected ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(selected ? PostStyle.accent : .primary)
                        }.buttonStyle(PostButtonStyle(inset: 0, selected: selected))
                            .accessibilityLabel(folder.name).help("\(folder.name): \(count) \(store.preferences.totalCounts ? "messages" : "unread messages")")
                            .contextMenu {
                                Button("Open \(folder.name)") { store.chooseFolder(folder.id) }
                                Button("Refresh") { store.chooseFolder(folder.id); Task { await store.refresh(manual: true) } }
                            }
                    }
                }.padding(.leading, 20).frame(width: 284, alignment: .leading)
            }.frame(width: 284)
            ZStack(alignment: .leading) {
                Button { store.showSettings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.buttonStyle(PostButtonStyle(inset: 0)).help("Settings")
                Button { showNewLabel = true } label: { Label("New label", systemImage: "plus").font(.system(size: 12)) }.offset(x: 58)
            }.frame(width: 264, height: 44, alignment: .leading).frame(width: store.preferences.collapsed ? 44 : 264, alignment: .leading).clipped().padding(.leading, 20).padding(.vertical, 12).foregroundStyle(PostStyle.secondary)
        }.frame(width: 284, alignment: .leading)
            .frame(width: store.preferences.collapsed ? 88 : 304, alignment: .leading)
            .clipped().background(PostStyle.sidebar)
    }
    private var emptyReading: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope").font(.system(size: 34, weight: .light))
            Text(store.folderID == "DRAFT" ? "Select a draft to continue writing" : "Select a message to read").font(.system(size: 18, weight: .medium))
            Text("Use \(store.preferences.shortcuts["previous"]?.display ?? "↑") and \(store.preferences.shortcuts["next"]?.display ?? "↓") to navigate").font(.system(size: 12))
        }.foregroundStyle(PostStyle.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.folder.name).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("\(store.folderID == "DRAFT" ? store.drafts.count : store.visibleMessages.count) messages").font(.system(size: 11)).foregroundStyle(PostStyle.secondary)
            }
            Spacer(minLength: 8)
            Button { Task { await store.refresh(manual: true) } } label: {
                if store.manualRefreshing { ProgressView().controlSize(.small).frame(width: 17, height: 17) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .regular)) }
            }.disabled(store.busy).help("Refresh mail").contextMenu { Button("Refresh mail") { Task { await store.refresh(manual: true) } } }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(PostStyle.secondary)
                TextField("Search mail", text: $store.search).textFieldStyle(.plain).focused($searchFocused)
                if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark") } }
            }.padding(10).background(PostStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10)).frame(width: 220)
            Button { store.newCompose() } label: {
                Label("Compose", systemImage: "square.and.pencil").font(.system(size: 13, weight: .medium)).foregroundStyle(PostStyle.buttonText).padding(.horizontal, 10).padding(.vertical, 6).background(PostStyle.accent, in: RoundedRectangle(cornerRadius: 9))
            }
            Menu { Text(store.account); if !store.connected { Button("Connect Gmail…") { store.showSettings = true } }; Button("Settings…") { store.showSettings = true } } label: {
                Text(String(store.account.prefix(2)).uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(PostStyle.accent).frame(width: 32, height: 32).background(PostStyle.selection, in: RoundedRectangle(cornerRadius: 9))
            }.menuStyle(.borderlessButton).fixedSize().pointerHover()
        }.padding(.horizontal, 22).frame(height: 93)
    }
    private var messageList: some View {
        VStack(spacing: 0) {
            if store.folderID == "DRAFT" {
                if store.drafts.isEmpty {
                    Text("No drafts here").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(store.drafts) { draft in
                                    Button { NSApp.keyWindow?.makeFirstResponder(nil); let flags = NSApp.currentEvent?.modifierFlags ?? []; store.clickMessage(draft.id, shift: flags.contains(.shift), command: flags.contains(.command)) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack { Text(draft.to.isEmpty ? "No recipient" : draft.to).font(.system(size: 14, weight: .medium)).lineLimit(1); Spacer(); Text(draft.updated.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }
                                            Text(draft.subject.isEmpty ? "Untitled draft" : draft.subject).font(.system(size: 12.5)).lineLimit(1)
                                            Text(draft.body).font(.system(size: 12)).lineLimit(1).foregroundStyle(.secondary)
                                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(store.bulkMode && store.bulkIDs.contains(draft.id) ? PostStyle.bulk : store.selectedDraftID == draft.id ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay { if store.bulkMode && store.bulkIDs.contains(draft.id) { RoundedRectangle(cornerRadius: 10).strokeBorder(PostStyle.accent.opacity(0.45), lineWidth: 1) } }
                                    }.buttonStyle(PostButtonStyle(inset: 0, selected: store.actionIDs.contains(draft.id))).padding(.horizontal, 14).id(draft.id)
                                        .contextMenu { if !store.bulkMode { Button("Edit draft") { store.select(draft.id) } }; Button(store.bulkMode && store.bulkIDs.contains(draft.id) ? "Delete selected drafts" : "Delete draft", role: .destructive) { store.prepareContextSelection(draft.id); store.draftsToDelete = store.drafts.filter { store.actionIDs.contains($0.id) } } }
                                }
                            }
                        }.onChange(of: store.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                    }
                }
            } else if store.visibleMessages.isEmpty {
                VStack(spacing: 12) { Image(systemName: store.search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary); Text(store.busy ? "Loading mail…" : store.search.isEmpty ? "No messages here" : "No matching messages").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(spacing: 0) { ForEach(store.visibleMessages) { message in MessageRow(message: message).id(message.id) }; if store.nextPage != nil { Button("Load more messages") { Task { await store.refresh(more: true) } }.padding(20).disabled(store.busy) } } }
                    .onChange(of: store.selectedID) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } } }
                }
            }
        }.background(PostStyle.background)
    }
    private var footer: some View {
        HStack(spacing: 15) {
            ForEach([("previous", ""), ("next", "Navigate"), ("reply", "Reply"), ("label", "Label"), ("trash", "Trash"), ("clear", "Clear selection")], id: \.0) { action, label in
                HStack(spacing: 5) { Text(store.preferences.shortcuts[action]?.display ?? "").font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 4).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 4)); if !label.isEmpty { Text(label).font(.system(size: 10)) } }.foregroundStyle(PostStyle.secondary)
            }
            Spacer(minLength: 4)
            Text(store.connected ? store.status : "Preview • local changes only").font(.system(size: 10)).foregroundStyle(PostStyle.secondary).lineLimit(1)
            if !store.connected { Button("Connect Gmail") { store.showSettings = true }.font(.system(size: 10)) }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct MessageRow: View {
    @EnvironmentObject var store: MailStore
    let message: MailMessage
    var body: some View {
        Button { NSApp.keyWindow?.makeFirstResponder(nil); let flags = NSApp.currentEvent?.modifierFlags ?? []; store.clickMessage(message.id, shift: flags.contains(.shift), command: flags.contains(.command)) } label: {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2).fill(message.unread ? PostStyle.accent : .clear).frame(width: 7, height: 7).padding(.top, 6)
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(SearchHighlight.text(message.senderName, query: store.search)).font(.system(size: 14, weight: message.unread ? .semibold : .medium)).lineLimit(1); Spacer(); Text(dateLabel).font(.system(size: 10)).foregroundStyle(PostStyle.secondary) }
                    HStack(spacing: 4) { if message.labels.contains("STARRED") { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange) }; Text(SearchHighlight.text(message.subject, query: store.search)).font(.system(size: 12.5, weight: message.unread ? .medium : .regular)).lineLimit(1); let files = message.attachments.filter { $0.contentID == nil }
                            if !files.isEmpty { Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(.secondary) } }
                    Text(SearchHighlight.text(searchSnippet, query: store.search)).font(.system(size: 12)).foregroundStyle(PostStyle.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 14).padding(.vertical, 15).frame(maxWidth: .infinity, alignment: .leading)
                .background(store.bulkMode && store.bulkIDs.contains(message.id) ? PostStyle.bulk : !store.bulkMode && store.selectedID == message.id ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay { if store.bulkMode && store.bulkIDs.contains(message.id) { RoundedRectangle(cornerRadius: 10).strokeBorder(PostStyle.accent.opacity(0.45), lineWidth: 1) } }
                .background(GeometryReader { geometry in Color.clear.preference(key: MessageFrames.self, value: [message.id: geometry.frame(in: .named("mailWindow"))]) }).contentShape(Rectangle())
        }.buttonStyle(PostButtonStyle(inset: 0, selected: store.actionIDs.contains(message.id))).accessibilityValue(store.bulkMode && store.bulkIDs.contains(message.id) ? "Selected for bulk actions" : !store.bulkMode && store.selectedID == message.id ? "Open message" : "").padding(.horizontal, 14).padding(.vertical, 3)
        .contextMenu {
            if !store.bulkMode { Button("Reply") { store.select(message.id); store.newCompose(kind: "reply") } }
            if message.labels.contains("TRASH") || message.labels.contains("SPAM") {
                Button("Move to Inbox") { store.prepareContextSelection(message.id); store.moveSelectedToInbox() }
            }
            Button("Apply label…") { store.prepareContextSelection(message.id); store.showLabels = true }
            Button("Archive") { store.prepareContextSelection(message.id); store.actOnSelected(add: [], remove: ["INBOX"], advance: true) }
            Button("Move to Trash") { store.prepareContextSelection(message.id); store.actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true) }
        }

    }
    private var searchSnippet: String {
        guard !store.search.isEmpty, !message.snippet.localizedCaseInsensitiveContains(store.search),
              let match = message.body.range(of: store.search, options: [.caseInsensitive, .diacriticInsensitive]) else { return message.snippet }
        let start = message.body.index(match.lowerBound, offsetBy: -35, limitedBy: message.body.startIndex) ?? message.body.startIndex
        let end = message.body.index(match.upperBound, offsetBy: 100, limitedBy: message.body.endIndex) ?? message.body.endIndex
        return (start == message.body.startIndex ? "" : "…") + message.body[start..<end].replacingOccurrences(of: "\n", with: " ")
    }
    private var dateLabel: String {
        if Calendar.current.isDateInToday(message.date) { return message.date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(message.date) { return "Yesterday" }
        return message.date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct ReadingPane: View {
    @EnvironmentObject var store: MailStore
    @LocalState private var plain = false
    var body: some View {
        Group {
            if let selected = store.selected {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Text("\(store.threadMessages.count) \(store.threadMessages.count == 1 ? "message" : "messages")").font(.system(size: 11)).foregroundStyle(PostStyle.secondary)
                        Spacer()
                        Button { store.newCompose(kind: "reply") } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }.help(store.preferences.shortcuts["reply"]?.display ?? "Reply")
                        Button { store.showLabels = true } label: { Label("Label", systemImage: "tag") }
                        Button { store.actOnSelected(add: [], remove: ["INBOX"], advance: true) } label: { Image(systemName: "archivebox") }.help("Archive")
                        Button { store.perform("trash") } label: { Label("Trash", systemImage: "trash") }
                        Menu {
                            Button("Reply all") { store.newCompose(kind: "replyAll") }
                            Button("Forward") { store.newCompose(kind: "forward") }
                            Button(selected.unread ? "Mark as read" : "Mark as unread") { store.actOnSelected(add: selected.unread ? [] : ["UNREAD"], remove: selected.unread ? ["UNREAD"] : []) }
                            Button(selected.labels.contains("STARRED") ? "Remove star" : "Star message") { store.actOnSelected(add: selected.labels.contains("STARRED") ? [] : ["STARRED"], remove: selected.labels.contains("STARRED") ? ["STARRED"] : []) }
                            Button(plain ? "Show formatted email" : "Show plain text") { plain.toggle() }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().pointerHover()
                    }.controlSize(.small).padding(.horizontal, 20).padding(.vertical, 14).frame(height: 61)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                Text(selected.subject).font(.system(size: 25, weight: .semibold)).textSelection(.enabled).padding(.bottom, 8)
                                ForEach(store.threadMessages) { message in
                                    ConversationMessage(message: message, plain: plain)
                                        .id(message.id)
                                        .padding(18)
                                        .background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).id("thread-top")
                        }
                        .onAppear { proxy.scrollTo("thread-top", anchor: .top) }
                        .onChange(of: store.selectedID) { _, _ in proxy.scrollTo("thread-top", anchor: .top) }
                        .id(selected.threadID)
                    }
                }
            }
        }.background(PostStyle.surface).onChange(of: store.selectedID) { _, _ in plain = false }
    }
}

struct ConversationMessage: View {
    @EnvironmentObject var store: MailStore
    let message: MailMessage
    let plain: Bool
    @LocalState private var allowImages = false
    @LocalState private var originalColors = false
    @LocalState private var showPlainQuote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(message.senderName.prefix(1)).uppercased()).font(.system(size: 20, weight: .medium)).foregroundStyle(PostStyle.background).frame(width: 38, height: 38).background(PostStyle.accent, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.senderName).font(.system(size: 14, weight: .semibold))
                    Text("\(message.senderAddress) · \(message.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(PostStyle.secondary).textSelection(.enabled)
                    Text("To: \(message.to)").font(.system(size: 10)).foregroundStyle(PostStyle.secondary).textSelection(.enabled)
                }
                Spacer()
                Menu {
                    Button("Reply") { store.newCompose(kind: "reply", replyingTo: message) }
                    Button("Reply all") { store.newCompose(kind: "replyAll", replyingTo: message) }
                    Button("Forward") { store.newCompose(kind: "forward", replyingTo: message) }
                    if !message.html.isEmpty { Button(originalColors ? "Use app colors" : "Use original email colors") { originalColors.toggle() } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().pointerHover()
            }
            if !message.html.isEmpty && !plain {
                if !allowImages && !store.preferences.remoteImages {
                    HStack { Text("Remote images are blocked").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Load images") { allowImages = true }.controlSize(.small) }
                }
                HTMLMessage(html: message.html, remoteImages: allowImages || store.preferences.remoteImages, originalColors: originalColors, foldQuotes: true)
                    .transaction { $0.animation = nil }.padding(.horizontal, 6).frame(minHeight: 100).clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                let parts = MessageQuote.split(message.body)
                Text(parts.body).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                if let quote = parts.quote {
                    DisclosureGroup("Quoted message", isExpanded: $showPlainQuote) {
                        Text(quote).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(.system(size: 12)).padding(.horizontal, 6)
                }
            }
            let files = message.attachments.filter { $0.contentID == nil }
            ForEach(files) { attachment in
                Button { store.download(attachment, message: message) } label: {
                    HStack { Image(systemName: "paperclip"); Text(attachment.name); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)); Image(systemName: "arrow.down") }.font(.system(size: 11)).padding(9).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(PostButtonStyle()).contextMenu { Button("Save attachment…") { store.download(attachment, message: message) } }
            }
            Button("Reply") { store.newCompose(kind: "reply", replyingTo: message) }.font(.system(size: 12)).buttonStyle(PostButtonStyle())
        }
    }
}

// Route trackpad and wheel input to the conversation instead of WebKit's inner scroller.
final class ThreadWebView: WKWebView {
    private var wheelMonitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
        guard window != nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            var parent = self.superview
            while let current = parent {
                if let scroll = current as? NSScrollView { scroll.scrollWheel(with: event); return nil }
                parent = current.superview
            }
            return event
        }
    }
    deinit { if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) } }
}

struct HTMLMessage: NSViewRepresentable {
    static let webDataStore = WKWebsiteDataStore.nonPersistent()
    let html: String
    let remoteImages: Bool
    var originalColors = false
    var foldQuotes = false
    @Environment(\.colorScheme) private var colorScheme
    @LocalState private var height: CGFloat = 100
    func makeCoordinator() -> Coordinator { Coordinator() }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: height)
    }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: """
        const measure = () => window.webkit.messageHandlers.postHeight.postMessage(document.body.getBoundingClientRect().height);
        if (\(foldQuotes)) {
            const candidates = [...document.querySelectorAll('.gmail_quote, .yahoo_quoted, blockquote, #divRplyFwdMsg')];
            candidates.filter(node => !candidates.some(other => other !== node && other.contains(node))).forEach(node => {
                const details = document.createElement('details'); details.className = 'post-quote';
                const summary = document.createElement('summary'); summary.textContent = 'Quoted message';
                node.before(details); details.append(summary);
                if (node.id === 'divRplyFwdMsg') {
                    while (details.nextSibling) details.append(details.nextSibling);
                } else { details.append(node); }
                details.addEventListener('toggle', measure);
            });
        }
        new ResizeObserver(measure).observe(document.body); measure();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "postHeight")
        config.websiteDataStore = Self.webDataStore;
        config.setURLSchemeHandler(PostImageLoader.shared, forURLScheme: "post-image"); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = ThreadWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; view.setValue(false, forKey: "drawsBackground"); return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.setHeight = { value in if abs(height - value) > 1 { height = value } }
        let signature = html + String(remoteImages) + String(colorScheme == .dark) + String(originalColors) + String(foldQuotes)
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        let images = remoteImages ? "post-image: data: cid:" : "data: cid:"
        let renderedHTML = remoteImages ? MessageHTML.cachedImageURLs(html) : html
        let dark = colorScheme == .dark && !originalColors
        let colors = originalColors ? "body{background:transparent;color:#242a34}" : "body{background:transparent!important;color:\(dark ? "#e5eaf1" : "#242a34")!important}p,span,td,div,li,table{color:inherit!important;background-color:transparent!important}a,a span{color:\(dark ? "#9ecafa" : "#176edc")!important}"
        let document = "<!doctype html><html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src \(images); style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'\"><style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;color:#242a34;margin:0;padding:12px 0;box-sizing:border-box;line-height:1.65;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}a{color:#176edc}html{overflow:hidden}details.post-quote{margin-top:14px}details.post-quote>summary{cursor:pointer;font-size:12px;color:#7d8b9c;user-select:none}details.post-quote[open]>summary{margin-bottom:12px}\(colors)</style></head><body>\(renderedHTML)</body></html>"
        view.loadHTMLString(document, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var signature = ""
        var setHeight: ((CGFloat) -> Void)?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let number = message.body as? NSNumber else { return }
            let value = min(max(CGFloat(number.doubleValue), 100), 30000)
            DispatchQueue.main.async { self.setHeight?(value) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.getBoundingClientRect().height") { value, _ in
                if let number = value as? NSNumber { self.setHeight?(min(max(CGFloat(number.doubleValue), 100), 30000)) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); decisionHandler(.cancel) }
            else if action.request.url?.absoluteString == "about:blank" { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}

struct LabelPicker: View {
    @EnvironmentObject var store: MailStore
    @LocalState private var labelAndArchive = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Apply label").font(.title2.bold()); Spacer(); Button("Done") { store.showLabels = false } }
            Toggle("Skip the inbox when applying a label", isOn: $labelAndArchive).font(.system(size: 12))
            ScrollView { VStack(spacing: 5) { ForEach(store.folders.filter(\.isCustom)) { folder in
                let targets = store.messages.filter { store.actionIDs.contains($0.id) }; let applied = !targets.isEmpty && targets.allSatisfy { $0.labels.contains(folder.id) }
                Button { if applied { store.actOnSelected(add: [], remove: [folder.id]) } else { store.actOnSelected(add: [folder.id], remove: labelAndArchive ? ["INBOX"] : [], advance: labelAndArchive) }; store.showLabels = false } label: { HStack { Image(systemName: folder.icon.replacingOccurrences(of: "circle", with: "square")); Text(folder.name); Spacer(); if applied { Image(systemName: "checkmark") } }.padding(11).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(PostButtonStyle())
            } } }
            if store.folders.filter(\.isCustom).isEmpty { Text("Create a label using the + button in the sidebar.").foregroundStyle(.secondary) }
        }.padding(24).frame(width: 430, height: 360)
    }
}

struct ComposePane: View {
    @EnvironmentObject var store: MailStore
    let initial: ComposeDraft
    let baseline: ComposeDraft
    var embedded = false
    @LocalState private var draft: ComposeDraft
    @LocalState private var showDismissPrompt = false
    @LocalState private var existedAtOpen = false
    @LocalState private var initialized = false
    @LocalState private var skipFinalSave = false
    @LocalState private var confirmDelete = false
    @LocalState private var sending = false
    @LocalState private var showCC = false
    @LocalState private var autosave: Task<Void, Never>?
    @FocusState private var bodyFocused: Bool
    init(initial: ComposeDraft, embedded: Bool = false) {
        self.initial = initial; self.embedded = embedded
        var value = initial; value.separateLegacyQuote()
        self.baseline = value
        _draft = LocalState(initialValue: value)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(draft.quotedText == nil ? "Compose" : "Reply").font(.system(size: 18, weight: .semibold)); Spacer(); if sending { ProgressView().controlSize(.small) }; Button("Save & close") { saveAndClose() }.disabled(sending); Button("Send") { sending = true; Task { _ = await store.send(draft); sending = false } }.buttonStyle(.borderedProminent).disabled(sending || draft.to.isEmpty || !store.connected)  ; Button { confirmDelete = true } label: { Image(systemName: "trash") }.help("Delete draft").disabled(sending) }.padding(20)
            Divider()
            HStack { Text("To").frame(width: 65, alignment: .leading).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary); TextField("", text: $draft.to).accessibilityLabel("To").textFieldStyle(.plain); Button("Cc/Bcc") { showCC.toggle() }.buttonStyle(PostButtonStyle()).font(.system(size: 11)).foregroundStyle(.secondary) }.padding(.horizontal, 22).padding(.vertical, 12)
            if showCC || !draft.cc.isEmpty || !draft.bcc.isEmpty { recipientRow("Cc", text: $draft.cc); recipientRow("Bcc", text: $draft.bcc) }
            Divider().padding(.horizontal, 22)
            HStack { Text("Subject").frame(width: 65, alignment: .leading).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary); TextField("", text: $draft.subject).accessibilityLabel("Subject").textFieldStyle(.plain) }.padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextEditor(text: $draft.body).focused($bodyFocused).font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: draft.quotedText == nil ? 280 : 170).accessibilityLabel("Message")
                    if let quote = draft.quotedText {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text(draft.quoteHeading ?? "Previous message").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Remove quote") { draft.quotedText = nil; draft.quotedHTML = nil; draft.quoteHeading = nil; scheduleSave() }.font(.system(size: 10)) }
                            HStack(alignment: .top, spacing: 16) {
                                RoundedRectangle(cornerRadius: 1).fill(PostStyle.accent.opacity(0.25)).frame(width: 2)
                                if let html = draft.quotedHTML, !html.isEmpty { HTMLMessage(html: html, remoteImages: false).frame(minHeight: 330) }
                                else { Text(quote).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }.padding(16).background(PostStyle.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .contextMenu { Button("Copy quoted message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(quote, forType: .string) }; Button("Remove quote") { draft.quotedText = nil; draft.quotedHTML = nil; draft.quoteHeading = nil; scheduleSave() } }
                    }
                }.padding(20)
            }
            if !draft.attachments.isEmpty { ScrollView(.horizontal) { HStack { ForEach(draft.attachments) { attachment in HStack { Image(systemName: "paperclip"); Text(attachment.name).lineLimit(1); Button { draft.attachments.removeAll { $0.id == attachment.id }; scheduleSave() } label: { Image(systemName: "xmark") }.buttonStyle(PostButtonStyle()) }.font(.system(size: 11)).padding(8).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 5)) } }.padding(.horizontal, 18) }.frame(height: 42) }
            Divider()
            HStack { Button { attach() } label: { Label("Attach files", systemImage: "paperclip") }; Spacer(); Text(store.connected ? "Drafts save automatically" : "Preview • sending is unavailable").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(16)
        }.animation(.easeInOut(duration: 0.22), value: showCC).buttonStyle(PostButtonStyle()).frame(width: embedded ? nil : 760, height: embedded ? nil : 620).frame(maxWidth: .infinity, maxHeight: .infinity).background(PostStyle.background).preferredColorScheme(PostStyle.scheme(store.preferences.appearance)).interactiveDismissDisabled(true)
        .onAppear { if !initialized { existedAtOpen = store.drafts.contains { $0.id == draft.id }; initialized = true; if !embedded && !draft.to.isEmpty { DispatchQueue.main.async { bodyFocused = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: 0, length: 0)); editor.scrollRangeToVisible(NSRange(location: 0, length: 0)) } } } } } }
        .onChange(of: store.composerDismissRequest) { _, _ in requestDismiss() }
        .postPrompt("Save draft?", isPresented: $showDismissPrompt, message: "Save your changes before closing?", actions: ["Save", "Keep writing", "Discard changes"]) { response in
            if response == 0 { saveAndClose() }
            else if response == 2 { discardAndClose() }
            else { scheduleSave() }
        }
        .postPrompt("Delete draft?", isPresented: $confirmDelete, message: "This deletes the draft from Post and Gmail if it has been synced.", actions: ["Delete", "Cancel"]) { response in
            if response == 0 { autosave?.cancel(); skipFinalSave = true; store.deleteDraft(draft); closeEditor() }
        }
        .onChange(of: draft.cc) { _, _ in scheduleSave() }.onChange(of: draft.bcc) { _, _ in scheduleSave() }
        .onChange(of: draft.to) { _, _ in scheduleSave() }.onChange(of: draft.subject) { _, _ in scheduleSave() }.onChange(of: draft.body) { _, _ in scheduleSave() }
        .onDisappear { autosave?.cancel(); if !skipFinalSave && !store.discardedDraftIDs.contains(draft.id) && (existedAtOpen || draft.hasUserChanges(from: baseline)) { store.saveDraft(draft, sync: false) } }
    }
    func recipientRow(_ label: String, text: Binding<String>) -> some View { HStack { Text(label).frame(width: 65, alignment: .leading).foregroundStyle(.secondary); TextField("", text: text).accessibilityLabel(label).textFieldStyle(.plain) }.padding(.horizontal, 22).padding(.vertical, 8) }
    private func closeEditor() {
        autosave?.cancel(); skipFinalSave = true
        if embedded { store.select(nil) } else { store.compose = nil }
    }
    private func saveAndClose() {
        if existedAtOpen || draft.hasUserChanges(from: baseline) { store.saveDraft(draft) }
        closeEditor()
    }
    private func discardAndClose() {
        autosave?.cancel(); skipFinalSave = true
        if existedAtOpen { store.saveDraft(baseline, sync: false) }
        else { store.deleteDraft(draft) }
        closeEditor()
    }
    private func requestDismiss() {
        guard !sending, !showDismissPrompt, !confirmDelete else { return }
        autosave?.cancel()
        if draft.hasUserChanges(from: baseline) { showDismissPrompt = true }
        else if existedAtOpen { closeEditor() }
        else { discardAndClose() }
    }
    private func scheduleSave() {
        autosave?.cancel()
        autosave = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, !skipFinalSave else { return }
            if existedAtOpen || draft.hasUserChanges(from: baseline) { store.saveDraft(draft, sync: false) }
            else if store.drafts.contains(where: { $0.id == draft.id }) {
                store.drafts.removeAll { $0.id == draft.id }; store.updateLocalCounts(); store.persist()
            }
        }
    }
    private func attach() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                do { let data = try Data(contentsOf: url); let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"; draft.attachments.append(.init(id: UUID().uuidString, name: url.lastPathComponent, mimeType: type, size: data.count, data: data)) }
                catch { store.error = error.localizedDescription }
            }
            scheduleSave()
        }
    }
}

struct SettingsPane: View {
    @EnvironmentObject var store: MailStore
    @LocalState private var section = "General"
    @LocalState private var shortcutText: [String: String] = [:]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) { Text("Settings").font(.system(size: 16, weight: .semibold)).padding(.bottom, 20); ForEach([("General", "gearshape"), ("Shortcuts", "keyboard"), ("Account", "person.crop.square")], id: \.0) { name, icon in Button { section = name } label: { Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(section == name ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(PostButtonStyle()) }; Spacer(); Button("Done") { store.showSettings = false }.keyboardShortcut(.defaultAction) }.padding(20).frame(width: 190).background(PostStyle.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 22) {
                Text(section).font(.system(size: 25, weight: .semibold))
                if section == "General" {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text("Sidebar counts").fontWeight(.medium); Text("The number beside each label uses this setting.").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Picker("", selection: $store.preferences.totalCounts) { Text("Unread").tag(false); Text("Total").tag(true) }.pickerStyle(.segmented).frame(width: 170) }
                    Divider()
                    Picker("Primary view", selection: Binding(get: { store.preferences.primaryMode ?? "wide" }, set: { store.preferences.primaryMode = $0; store.currentRemoteIDs = nil; store.select(nil); if store.connected { Task { await store.refresh() } } else { store.updateLocalCounts() } })) { Text("Gmail Primary category").tag("gmail"); Text("Inbox except Promotions and Newsletters").tag("wide") }
                    Toggle("Mark messages as read when opened", isOn: $store.preferences.markRead)
                    Toggle("Show new-mail notifications", isOn: $store.preferences.notifications).onChange(of: store.preferences.notifications) { _, value in if value { store.enableNotifications() } }
                    Toggle("Load remote images automatically", isOn: $store.preferences.remoteImages)
                    Divider(); Text("Signature").fontWeight(.medium); TextEditor(text: $store.preferences.signature).font(.system(size: 12)).frame(height: 90).border(Color.gray.opacity(0.2))
                    Picker("Appearance", selection: Binding(get: { store.preferences.appearance ?? "system" }, set: { store.preferences.appearance = $0 })) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
                } else if section == "Shortcuts" {
                    Text("Click Record, then press your shortcut. Changes update menus and hints immediately.").font(.system(size: 11)).foregroundStyle(.secondary)
                    ScrollView { VStack(spacing: 0) { ForEach(Shortcut.names, id: \.0) { action, name in
                        HStack { Text(name).font(.system(size: 12)); Spacer(); Text(store.preferences.shortcuts[action]?.display ?? "").font(.system(size: 12, weight: .medium)).frame(width: 80).padding(6).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 5)); Button(store.recordingShortcut == action ? "Press keys…" : "Record") { store.recordingShortcut = action }.font(.system(size: 10)).frame(width: 80) }.padding(.vertical, 9); Divider()
                    } } }
                    Button("Restore defaults") { store.preferences.shortcuts = Shortcut.defaults; store.recordingShortcut = nil }
                } else {
                    Text(store.connected ? store.account : "No Gmail account connected").font(.system(size: 14, weight: .medium)).textSelection(.enabled)
                    Text(store.connected ? "Connected to Gmail" : "Connect your Gmail account using your Google Desktop OAuth client.").font(.system(size: 12)).foregroundStyle(.secondary)
                    if store.connected { Button("Disconnect Gmail") { store.disconnect() } }
                    else {
                        Text("1. Import the JSON file for your Google Desktop OAuth client.\n2. Sign in using your browser.").font(.system(size: 12)).lineSpacing(7)
                        Button(store.hasClient ? "Replace Google client…" : "Import Google client…") { store.importOAuth() }
                        Button(store.busy ? "Waiting for sign-in…" : "Sign in with Google") { store.signIn() }.buttonStyle(.borderedProminent).disabled(!store.hasClient || store.busy)
                        Button("Open setup guide") { if let url = Bundle.main.url(forResource: "Setup", withExtension: "md") { NSWorkspace.shared.open(url) } }.font(.system(size: 11))
                    }
                    Divider(); Text("Sign-in is stored in macOS Keychain. Cached mail and drafts stay on this Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.animation(.easeInOut(duration: 0.2), value: section).buttonStyle(PostButtonStyle()).frame(width: 760, height: 600).background(PostStyle.background).preferredColorScheme(PostStyle.scheme(store.preferences.appearance))
        .onDisappear { store.recordingShortcut = nil }
        .onChange(of: store.preferences.totalCounts) { _, _ in if store.connected { Task { await store.refresh() } } }
    }
}

struct PointerHover: ViewModifier {
    @LocalState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.onHover { value in
            let next = value && enabled
            guard next != hovering else { return }
            hovering = next
            if next { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }.onDisappear { if hovering { NSCursor.pop(); hovering = false } }
    }
}
extension View {
    func pointerHover() -> some View { modifier(PointerHover()) }
}
struct PostButtonStyle: ButtonStyle {
    var inset: CGFloat = 5
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        PostButtonBody(configuration: configuration, inset: inset, selected: selected)
    }
}
private struct PostButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let inset: CGFloat
    let selected: Bool
    @LocalState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label.padding(inset)
            .background(PostStyle.accent.opacity(enabled && hovering && !selected ? 0.075 : 0), in: RoundedRectangle(cornerRadius: 10))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion && !selected ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovering = $0 }
            .pointerHover()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ view: NSView, context: Context) {}
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = true
        }
    }
}

struct MessageFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
struct CardFlight: ViewModifier {
    var x: CGFloat
    var y: CGFloat
    var sx: CGFloat
    var sy: CGFloat
    var opacity: Double
    func body(content: Content) -> some View { content.scaleEffect(x: sx, y: sy).offset(x: x, y: y).opacity(opacity) }
}

struct RefreshStrip: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            if active {
                if reduceMotion {
                    Rectangle().fill(PostStyle.accent.opacity(0.5))
                } else {
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                            let rect = CGRect(x: CGFloat(phase) * size.width * 1.3 - size.width * 0.3, y: 0, width: size.width * 0.3, height: size.height)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(PostStyle.accent.opacity(0.65)))
                        }
                    }.transaction { $0.animation = nil }
                }
            }
        }.clipped().accessibilityLabel(active ? "Refreshing mail" : "").accessibilityHidden(!active)
            .transaction { $0.animation = nil }
    }
}

struct BulkSelectionPane: View {
    @EnvironmentObject var store: MailStore
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.stack").font(.system(size: 32, weight: .light)).foregroundStyle(PostStyle.accent)
            Text("\(store.bulkIDs.count) \(store.folderID == "DRAFT" ? "drafts" : "messages") selected").font(.system(size: 20, weight: .medium))
            if store.folderID == "DRAFT" {
                Button { store.perform("trash") } label: { Label("Delete drafts", systemImage: "trash") }.buttonStyle(PostButtonStyle())
            } else {
            HStack(spacing: 14) {
                Button { store.showLabels = true } label: { Label("Move to label", systemImage: "tag") }
                Button { store.actOnSelected(add: [], remove: ["INBOX"], advance: true) } label: { Label("Archive", systemImage: "archivebox") }
                Button { store.actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true) } label: { Label("Trash", systemImage: "trash") }
            }.buttonStyle(PostButtonStyle()).font(.system(size: 12))
            }
            Text("Shift-click to select a range. Command-click to add or remove a message.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Clear selection") { store.select(nil) }.font(.system(size: 11))
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Explicit AppKit key equivalents also allow destructive defaults on Return.
extension View {
    func postPrompt(_ title: String, isPresented: Binding<Bool>, message: String, actions: [String], response: @escaping (Int) -> Void) -> some View {
        background(PostPromptPresenter(presented: isPresented, title: title, message: message, actions: actions, response: response).frame(width: 0, height: 0))
    }
}

struct PostPromptPresenter: NSViewRepresentable {
    @Binding var presented: Bool
    let title: String
    let message: String
    let actions: [String]
    let response: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        guard presented, !context.coordinator.active else { return }
        context.coordinator.active = true
        DispatchQueue.main.async {
            guard let window = view.window else { context.coordinator.active = false; return }
            let alert = NSAlert()
            alert.messageText = title; alert.informativeText = message
            for (index, name) in actions.enumerated() {
                let button = alert.addButton(withTitle: name)
                button.keyEquivalent = index == 0 ? "\r" : index == 1 ? "\u{1b}" : ""
            }
            PostDelegate.promptCount += 1
            alert.beginSheetModal(for: window) { result in
                PostDelegate.promptCount -= 1
                context.coordinator.active = false
                response(result.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
                presented = false
            }
        }
    }
    final class Coordinator { var active = false }
}

/// Highlight the loaded list without changing its contents or triggering Gmail requests.
enum SearchHighlight {
    static func text(_ value: String, query: String) -> AttributedString {
        var result = AttributedString(value)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return result }
        var remaining = value.startIndex..<value.endIndex
        while let range = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
            if let start = AttributedString.Index(range.lowerBound, within: result), let end = AttributedString.Index(range.upperBound, within: result) {
                result[start..<end].backgroundColor = Color.yellow.opacity(0.35)
            }
            guard range.upperBound < value.endIndex else { break }
            remaining = range.upperBound..<value.endIndex
        }
        return result
    }
}

/// Remote images share a bounded cache across messages, without cookies or sender scripts.
final class PostImageLoader: NSObject, WKURLSchemeHandler {
    static let shared = PostImageLoader()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024, diskPath: "Post-RemoteImages")
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let original = MessageHTML.originalImageURL(url) else { task.didFailWithError(URLError(.badURL)); return }
        let key = ObjectIdentifier(task)
        let request = URLRequest(url: original)
        let download = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard self?.tasks.removeValue(forKey: key) != nil else { return }
                if let error { task.didFailWithError(error); return }
                guard let data, let response, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { task.didFailWithError(URLError(.badServerResponse)); return }
                task.didReceive(URLResponse(url: url, mimeType: response.mimeType, expectedContentLength: data.count, textEncodingName: response.textEncodingName))
                task.didReceive(data); task.didFinish()
            }
        }
        tasks[key] = download; download.resume()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { tasks.removeValue(forKey: ObjectIdentifier(task))?.cancel() }
}
