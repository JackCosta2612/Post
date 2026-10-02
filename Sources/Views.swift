import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

typealias LocalState<Value> = SwiftUI.State<Value>

final class PostPalette: ObservableObject {
    static let shared = PostPalette()
    @Published var interfaceFont = "SF Pro Display"
    @Published var name = "blue"
    @Published var hex = "3B6EA3"
}
enum PostStyle {
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom(PostPalette.shared.interfaceFont, size: size).weight(weight) }
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let background = adaptive(NSColor(srgbRed: 0.965, green: 0.974, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1))
    static let sidebar = adaptive(NSColor(srgbRed: 0.935, green: 0.95, blue: 0.96, alpha: 1), NSColor(srgbRed: 0.07, green: 0.09, blue: 0.12, alpha: 1))
    static let surface = adaptive(.white, NSColor(srgbRed: 0.13, green: 0.16, blue: 0.20, alpha: 1))
    static let defaultAccent = adaptive(NSColor(srgbRed: 0.23, green: 0.43, blue: 0.64, alpha: 1), NSColor(srgbRed: 0.54, green: 0.73, blue: 0.94, alpha: 1))
    static let defaultSelection = adaptive(NSColor(srgbRed: 0.89, green: 0.94, blue: 0.995, alpha: 1), NSColor(srgbRed: 0.18, green: 0.28, blue: 0.39, alpha: 1))
    static var accentName: String { get { PostPalette.shared.name } set { if PostPalette.shared.name != newValue { PostPalette.shared.name = newValue } } }
    static var accent: Color { accentName == "blue" ? defaultAccent : Color(nsColor: accentNS) }
    static var selection: Color { accentName == "blue" ? defaultSelection : accent.opacity(0.14) }
    static var accentNS: NSColor { switch accentName { case "custom": return NSColor(postHex: PostPalette.shared.hex) ?? .systemBlue; case "purple": return .systemPurple; case "green": return .systemGreen; case "orange": return .systemOrange; case "pink": return .systemPink; case "gray": return .systemGray; default: return .systemBlue } }
    static let bulk = adaptive(NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.19, green: 0.23, blue: 0.29, alpha: 1))
    static let buttonText = adaptive(.white, NSColor(srgbRed: 0.07, green: 0.12, blue: 0.19, alpha: 1))
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let subtle = adaptive(NSColor(white: 0, alpha: 0.035), NSColor(white: 1, alpha: 0.055))
    static func scheme(_ preference: String?) -> ColorScheme? {
        preference == "dark" ? .dark : preference == "light" ? .light : nil
    }
}

struct MailWindow: View {
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    @LocalState private var rowFrames: [String: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @LocalState private var newLabel = ""
    @LocalState private var showNewLabel = false
    private var configuredWindow: some View {
        windowLayout
        .onAppear { configurePresentation(); DispatchQueue.main.async { if store.compose == nil && store.selectedDraftID == nil { NSApp.keyWindow?.makeFirstResponder(nil) } } }
        .onChange(of: store.preferences.interfaceFont) { _, _ in configurePresentation() }
        .onChange(of: store.preferences.accentColor) { _, _ in configurePresentation() }
        .onChange(of: store.preferences.accentHex) { _, _ in configurePresentation() }
        .onChange(of: store.visibleMessages.map(\.id)) { _, _ in if store.preferences.cacheMode == "fast" { configurePresentation() } }
        .onChange(of: store.preferences.readDelay) { _, _ in if let id = store.selectedID { store.scheduleRead(id) } }
        .onChange(of: store.preferences.markRead) { _, _ in if let id = store.selectedID { store.scheduleRead(id) } }
        .onChange(of: store.preferences.cacheMode) { _, _ in configurePresentation(); store.warmNearbyThreads() }
        .coordinateSpace(name: "mailWindow")
        .onPreferenceChange(MessageFrames.self) { rowFrames = $0 }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChrome())
        .buttonStyle(PostButtonStyle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.preferences.collapsed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.selectedID != nil && !store.bulkMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.selectedDraftID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bulkIDs)
        .background(PostStyle.background)
        .foregroundStyle(.primary)
        .tint(PostStyle.accent)
        .font(PostStyle.font(size: 13))
        .frame(minWidth: 980, minHeight: 630)
        .preferredColorScheme(PostStyle.scheme(store.preferences.appearance))

    }
    var body: some View {
        configuredWindow
        .accessibilityHidden(store.showSettings)
        .overlay {
            if store.showSettings {
                ZStack {
                    Button { store.showSettings = false } label: {
                        Rectangle().fill(Color.black.opacity(0.14)).contentShape(Rectangle())
                    }.buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea().accessibilityLabel("Close Settings")
                    SettingsPane().environmentObject(store)
                        .accessibilityHidden(store.demoMode)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                        .onExitCommand { store.showSettings = false }
                }
            }
        }
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
    private var windowLayout: some View {
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
                if store.preferences.showShortcutHints != false || store.undoSendID != nil { footer }
            }
        }
    }
    private func sidebarRow(_ folder: MailFolder) -> some View {
                        let count = folder.id == "TRASH" || store.preferences.sidebarBadges == false ? 0 : (store.preferences.totalCounts ? folder.totalCount : folder.unreadCount)
                        let selected = store.folderID == folder.id
                        return Button { NSApp.keyWindow?.makeFirstResponder(nil); store.chooseFolder(folder.id) } label: {
                            ZStack(alignment: .leading) {
                                Image(systemName: folder.icon.replacingOccurrences(of: "circle", with: "square"))
                                    .font(PostStyle.font(size: 17, weight: .regular)).frame(width: 44, height: 44)
                                    .offset(x: store.preferences.collapsed ? 0 : 6)
                                Text(folder.name).font(PostStyle.font(size: 13, weight: selected ? .medium : .regular))
                                    .lineLimit(1).frame(width: 166, alignment: .leading).offset(x: 58)
                                if count > 0 {
                                    Text(count > 9999 ? "9k+" : String(count)).font(PostStyle.font(size: 11, weight: .medium)).monospacedDigit()
                                        .foregroundStyle(selected ? PostStyle.accent : PostStyle.secondary)
                                        .frame(width: 25, alignment: .trailing).offset(x: 230)
                                }
                            }.frame(width: 264, height: 44, alignment: .leading)
                                .frame(width: store.preferences.collapsed ? 44 : 264, alignment: .leading).clipped()
                                .background(selected ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(selected ? PostStyle.accent : .primary)
                                .overlay(alignment: .topTrailing) {
                                    if store.preferences.collapsed && count > 0 {
                                        Text(count > 99 ? "99+" : String(count))
                                            .font(PostStyle.font(size: 9, weight: .semibold)).monospacedDigit()
                                            .foregroundStyle(.white).padding(.horizontal, 4)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(PostStyle.accent, in: RoundedRectangle(cornerRadius: 5))
                                            .offset(x: 3, y: -2).allowsHitTesting(false)
                                    }
                                }
                            .background(MailDragSurface(payload: folder.id != "primary" && (folder.isCustom || folder.id == "CATEGORY_PROMOTIONS") ? "post-label:" + folder.id : nil, title: folder.name))
                        }.buttonStyle(PostButtonStyle(inset: 0, selected: selected))
                            .accessibilityLabel(folder.name).help(folder.id == "TRASH" ? folder.name : "\(folder.name): \(count) \(store.preferences.totalCounts ? "messages" : "unread messages")")
                            .modifier(LabelDropTarget(id: folder.id, height: 44, store: store, acceptsMessages: true))
                            .overlay(alignment: .trailing) {
                                if showLabelHints, let shortcut = store.shortcutLabels().first(where: { $0.0.id == folder.id })?.1 {
                                    Text(shortcut.key.uppercased()).font(PostStyle.font(size: 11, weight: .semibold)).frame(width: 22, height: 22).background(PostStyle.surface, in: RoundedRectangle(cornerRadius: 5)).padding(.trailing, store.preferences.collapsed ? 0 : 9).allowsHitTesting(false)
                                }
                            }
                            .contextMenu {
                                Button("Open \(folder.name)") { store.chooseFolder(folder.id) }
                                Button("Refresh") { store.chooseFolder(folder.id); Task { await store.refresh(manual: true) } }
                            }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Button { store.preferences.collapsed.toggle() } label: {
                    Image(systemName: "sidebar.left").font(PostStyle.font(size: 16)).frame(width: 44, height: 38)
                }.buttonStyle(PostButtonStyle(inset: 0)).help(store.preferences.collapsed ? "Expand sidebar" : "Collapse sidebar")
                Text("Post").font(PostStyle.font(size: 14, weight: .semibold)).foregroundStyle(PostStyle.secondary).offset(x: 218)
            }.frame(width: 264, height: 38, alignment: .leading).padding(.leading, 20).padding(.top, 43).padding(.bottom, 12)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.sidebarLabels) { folder in sidebarRow(folder) }
                        }.padding(.leading, 20).padding(.top, 3).padding(.bottom, 3).frame(width: 284, alignment: .leading)
                    }
                    if CGFloat(store.sidebarLabels.count * 52 - 8 + 6) > geometry.size.height {
                        Rectangle().fill(PostStyle.secondary.opacity(0.15)).frame(height: 1).padding(.horizontal, 20)
                    }
                }
            }.frame(width: store.preferences.collapsed ? 88 : 304)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.sidebarFilters) { folder in sidebarRow(folder) }
            }.padding(.leading, 20).padding(.top, 16).frame(width: 284, alignment: .leading)
            ZStack(alignment: .leading) {
                Button { store.showSettings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.buttonStyle(PostButtonStyle(inset: 0)).help("Settings")
                Button { showNewLabel = true } label: { Label("New label", systemImage: "plus").font(PostStyle.font(size: 12)) }.offset(x: 58)
            }.frame(width: 264, height: 44, alignment: .leading).frame(width: store.preferences.collapsed ? 44 : 264, alignment: .leading).clipped().padding(.leading, 20).padding(.vertical, 12).foregroundStyle(PostStyle.secondary)
        }.frame(width: 284, alignment: .leading)
            .frame(width: store.preferences.collapsed ? 88 : 304, alignment: .leading)
            .clipped().background(PostStyle.sidebar)
    }
    private var emptyReading: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope").font(PostStyle.font(size: 34, weight: .light))
            Text(store.folderID == "DRAFT" ? "Select a draft to continue writing" : "Select a message to read").font(PostStyle.font(size: 18, weight: .medium))
            Text("Use \(store.preferences.shortcuts["previous"]?.display ?? "↑") and \(store.preferences.shortcuts["next"]?.display ?? "↓") to navigate").font(PostStyle.font(size: 12))
        }.foregroundStyle(PostStyle.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(store.folder.name).font(PostStyle.font(size: 20, weight: .semibold)).lineLimit(1)
                    if store.folderID != "DRAFT" {
                        Button { store.toggleUnreadFilter() } label: {
                            Label("Unread", systemImage: store.unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                                .font(PostStyle.font(size: 11, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(store.unreadOnly ? PostStyle.accent : PostStyle.secondary)
                                .background(store.unreadOnly ? PostStyle.selection : PostStyle.subtle, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(PostButtonStyle(selected: store.unreadOnly)).help("Show unread messages in this section").accessibilityValue(store.unreadOnly ? "On" : "Off")
                    }
                }
                Text("\(store.sectionCount) \(store.unreadOnly ? "unread messages" : "messages")").font(PostStyle.font(size: 11)).foregroundStyle(PostStyle.secondary)
            }
            Spacer(minLength: 8)
            Button { Task { await store.refresh(manual: true) } } label: {
                if store.manualRefreshing { ProgressView().controlSize(.small).frame(width: 17, height: 17) }
                else { Image(systemName: "arrow.clockwise").font(PostStyle.font(size: 15, weight: .regular)) }
            }.disabled(store.busy).help("Refresh mail").contextMenu { Button("Refresh mail") { Task { await store.refresh(manual: true) } } }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(PostStyle.secondary)
                TextField("Search mail", text: $store.search).textFieldStyle(.plain).focused($searchFocused)
                if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark") } }
            }.padding(10).background(PostStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10)).frame(width: 220)
            Button { store.newCompose() } label: {
                Label("Compose", systemImage: "square.and.pencil").font(PostStyle.font(size: 13, weight: .medium)).foregroundStyle(PostStyle.buttonText).padding(.horizontal, 10).padding(.vertical, 6).background(PostStyle.accent, in: RoundedRectangle(cornerRadius: 9))
            }
            Menu { Text(store.account); if !store.connected { Button("Connect Gmail…") { store.showSettings = true } }; Button("Settings…") { store.showSettings = true }; Button("Check for updates…") { PostUpdates.shared.openAccount = true; store.showSettings = true; Task { await PostUpdates.shared.check() } } } label: {
                Text(String(store.account.prefix(2)).uppercased()).font(PostStyle.font(size: 12, weight: .semibold)).foregroundStyle(PostStyle.accent).frame(width: 32, height: 32).background(PostStyle.selection, in: RoundedRectangle(cornerRadius: 9))
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
                                            HStack { Text(draft.to.isEmpty ? "No recipient" : draft.to).font(PostStyle.font(size: store.preferences.listSize ?? 14, weight: .medium)).lineLimit(1); Spacer(); Text(draft.updated.formatted(date: .omitted, time: .shortened)).font(PostStyle.font(size: 10)).foregroundStyle(.secondary) }
                                            Text(draft.subject.isEmpty ? "Untitled draft" : draft.subject).font(PostStyle.font(size: (store.preferences.listSize ?? 14) - 1.5)).lineLimit(1)
                                            Text(draft.scheduledAt.map { "Scheduled: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? (draft.deliveryState == "uncertain" ? "Check Sent before retrying" : draft.body)).font(PostStyle.font(size: 12)).lineLimit(1).foregroundStyle(.secondary)
                                        }.padding(.horizontal, 14).padding(.vertical, store.preferences.listDensity == "compact" ? 9 : store.preferences.listDensity == "spacious" ? 21 : 14).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(store.bulkMode && store.bulkIDs.contains(draft.id) ? PostStyle.bulk : store.selectedDraftID == draft.id ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay { if store.bulkMode && store.bulkIDs.contains(draft.id) { RoundedRectangle(cornerRadius: 10).strokeBorder(PostStyle.accent.opacity(0.45), lineWidth: 1) } }
                                    }.buttonStyle(PostButtonStyle(inset: 0, selected: store.actionIDs.contains(draft.id))).padding(.horizontal, 14).id(draft.id)
                                        .contextMenu { if !store.bulkMode { Button("Edit draft") { store.select(draft.id) } }; Button(store.bulkMode && store.bulkIDs.contains(draft.id) ? "Delete selected drafts" : "Delete draft", role: .destructive) { store.prepareContextSelection(draft.id); store.draftsToDelete = store.drafts.filter { store.actionIDs.contains($0.id) } } }
                                }
                            }
                        }.onChange(of: store.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id) } } }
                    }
                }
            } else if store.awaitingFolderList {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.visibleMessages.isEmpty {
                VStack(spacing: 12) { Image(systemName: store.search.isEmpty ? "tray" : "magnifyingglass").font(PostStyle.font(size: 28)).foregroundStyle(.tertiary); Text(store.search.isEmpty ? "No messages here" : "No matching messages").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(spacing: 0) { ForEach(store.visibleMessages) { message in MessageRow(message: message).id(message.id) }; if store.nextPage != nil { Button("Load more messages") { Task { await store.refresh(more: true) } }.padding(20).disabled(store.busy) } } }
                    .onChange(of: store.selectedID) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
                }
            }
        }.background(PostStyle.background).id(store.folderCacheKey)
    }
    private func configurePresentation() {
        PostPalette.shared.interfaceFont = store.preferences.interfaceFont ?? "SF Pro Display"
        PostStyle.accentName = store.preferences.accentColor ?? "blue"
        PostPalette.shared.hex = store.preferences.accentHex ?? "3B6EA3"
        HTMLDocument.cacheLimit = store.preferences.cacheMode == "fast" ? 120 : 40
        PostImageLoader.shared.configure(mode: store.preferences.cacheMode ?? "balanced", directory: store.directory)
        if store.preferences.remoteImages, store.preferences.cacheMode == "fast" { for message in store.visibleMessages.prefix(6) { PostImageLoader.shared.prefetch(message.html) } }
    }
    private var showLabelHints: Bool {
        store.commandHeld && store.selectedID == nil && store.compose == nil && store.selectedDraftID == nil && !searchFocused && !store.showSettings && !(NSApp.keyWindow?.firstResponder is NSTextView) && !(NSApp.keyWindow?.firstResponder is NSTextField)
    }
    private var footer: some View {
        HStack(spacing: 15) {
            if store.preferences.showShortcutHints != false { ForEach([("previous", ""), ("next", "Navigate"), ("reply", "Reply"), ("label", "Label"), ("trash", "Trash"), ("clear", "Clear selection")], id: \.0) { action, label in
                HStack(spacing: 5) { Text(store.preferences.shortcuts[action]?.display ?? "").font(PostStyle.font(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 4).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 4)); if !label.isEmpty { Text(label).font(PostStyle.font(size: 10)) } }.foregroundStyle(PostStyle.secondary)
            }
            }
            if store.undoSendID != nil { Button("Undo Send") { store.undoSend() }.font(PostStyle.font(size: 12, weight: .semibold)) }
            Spacer(minLength: 4)
            Text(store.connected ? store.status : "Preview • local changes only").font(PostStyle.font(size: 10)).foregroundStyle(PostStyle.secondary).lineLimit(1)
            if !store.connected { Button("Connect Gmail") { store.showSettings = true }.font(PostStyle.font(size: 10)) }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct MessageRow: View {
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    let message: MailMessage
    var body: some View {
        Button { NSApp.keyWindow?.makeFirstResponder(nil); let flags = NSApp.currentEvent?.modifierFlags ?? []; store.clickMessage(message.id, shift: flags.contains(.shift), command: flags.contains(.command)) } label: {
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 2).fill(message.unread ? PostStyle.accent : .clear).frame(width: 7, height: 7).padding(.top, 6)
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(SearchHighlight.text(message.senderName, query: store.search)).font(PostStyle.font(size: store.preferences.listSize ?? 14, weight: message.unread && store.preferences.boldUnread != false ? .bold : .medium)).lineLimit(1); Spacer(); Text(dateLabel).font(PostStyle.font(size: 10)).foregroundStyle(PostStyle.secondary) }
                    HStack(spacing: 4) { if message.labels.contains("STARRED") { Image(systemName: "star.fill").font(PostStyle.font(size: 10)).foregroundStyle(.orange) }; Text(SearchHighlight.text(message.subject, query: store.search)).font(PostStyle.font(size: (store.preferences.listSize ?? 14) - 1.5, weight: message.unread && store.preferences.boldUnread != false ? .semibold : .regular)).lineLimit(1); let files = message.attachments.filter { $0.contentID == nil }
                            if !files.isEmpty { Image(systemName: "paperclip").font(PostStyle.font(size: 10)).foregroundStyle(.secondary) } }
                    Text(SearchHighlight.text(searchSnippet, query: store.search)).font(PostStyle.font(size: 12)).foregroundStyle(PostStyle.secondary).lineLimit(1)
                }
            }.padding(.horizontal, 14).padding(.vertical, store.preferences.listDensity == "compact" ? 9 : store.preferences.listDensity == "spacious" ? 21 : 15).frame(maxWidth: .infinity, alignment: .leading)
                .background(store.bulkMode && store.bulkIDs.contains(message.id) ? PostStyle.bulk : !store.bulkMode && store.selectedID == message.id ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay { if store.bulkMode && store.bulkIDs.contains(message.id) { RoundedRectangle(cornerRadius: 10).strokeBorder(PostStyle.accent.opacity(0.45), lineWidth: 1) } }
                .background(GeometryReader { geometry in Color.clear.preference(key: MessageFrames.self, value: [message.id: geometry.frame(in: .named("mailWindow"))]) }).contentShape(Rectangle())
                .background(MailDragSurface(payload: store.messageDragPayload(message.id), title: message.subject))
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
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    @LocalState private var plain = false
    @LocalState private var centeringID: String?
    @LocalState private var selectedBodyReady = false
    @LocalState private var positionedID: String?
    private var scrollTarget: String {
        store.threadMessages.first?.id == store.selectedID ? "thread-top" : (store.selectedID ?? "thread-top")
    }
    @LocalState private var centerTask: Task<Void, Never>?
    private func settleCenter(_ proxy: ScrollViewProxy, readyID: String) {
        guard let target = centeringID, target == store.selectedID else { return }
        if readyID == target { selectedBodyReady = true }
        centerTask?.cancel()
        centerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, centeringID == target, store.selectedID == target, selectedBodyReady else { return }
            proxy.scrollTo(scrollTarget, anchor: .top)
            await Task.yield()
            guard !Task.isCancelled, store.selectedID == target else { return }
            positionedID = target
            centeringID = nil
        }
    }
    var body: some View {
        Group {
            if let selected = store.selected {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Text("\(store.threadMessages.count) \(store.threadMessages.count == 1 ? "message" : "messages")").font(PostStyle.font(size: 11)).foregroundStyle(PostStyle.secondary)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selected.subject).font(PostStyle.font(size: 23, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        let labels = store.folders.filter { selected.labels.contains($0.id) && ($0.isCustom || $0.id == "CATEGORY_PROMOTIONS") }
                        if !labels.isEmpty { FlowLabelChips(labels: labels) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 16)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(store.threadMessages) { message in
                                    if message.id != store.threadMessages.first?.id {
                                        Rectangle().fill(PostStyle.accent.opacity(0.5)).frame(height: 1).padding(.horizontal, 18).accessibilityHidden(true)
                                    }
                                    ConversationMessage(message: message, plain: plain, onLayoutReady: { settleCenter(proxy, readyID: message.id) })
                                        .id(message.id)
                                        .padding(18)
                                        .background(PostStyle.adaptive(.white, NSColor(srgbRed: 0.16, green: 0.19, blue: 0.23, alpha: 1)), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).id("thread-top")
                        }
                        .opacity(store.threadMessages.count <= 1 || positionedID == selected.id ? 1 : 0)
                        .task(id: selected.id) {
                            centerTask?.cancel(); centeringID = selected.id; selectedBodyReady = selected.html.isEmpty || plain
                            if store.threadMessages.count <= 1 {
                                centeringID = nil; positionedID = selected.id
                                proxy.scrollTo("thread-top", anchor: .top)
                                return
                            }
                            proxy.scrollTo(scrollTarget, anchor: .top)
                            await Task.yield()
                            guard !Task.isCancelled, store.selectedID == selected.id else { return }
                            proxy.scrollTo(scrollTarget, anchor: .top)
                            if selectedBodyReady { settleCenter(proxy, readyID: selected.id) }
                        }
                        .onChange(of: store.threadMessages.map(\.id)) { _, _ in
                            guard store.threadMessages.count > 1 else { proxy.scrollTo("thread-top", anchor: .top); positionedID = selected.id; return }
                            centeringID = selected.id
                            proxy.scrollTo(scrollTarget, anchor: .top)
                            settleCenter(proxy, readyID: selected.id)
                        }
                        .onDisappear { centerTask?.cancel() }
                        .id(selected.id)
                    }
                }
            }
        }.animation(nil, value: store.selectedID).background(PostStyle.surface).onChange(of: store.selectedID) { _, _ in plain = false }
    }
}

struct ConversationMessage: View {
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    let message: MailMessage
    let plain: Bool
    var onLayoutReady: (() -> Void)? = nil
    @LocalState private var allowImages = false
    @LocalState private var originalColors: Bool? = nil
    private var useOriginalColors: Bool { originalColors ?? (store.preferences.customEmailColors != true) }
    @LocalState private var showPlainQuote = false
    @LocalState private var htmlReady = false
    private var ready: Bool { message.html.isEmpty || plain || htmlReady }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Text(String(message.senderName.prefix(1)).uppercased()).font(PostStyle.font(size: 20, weight: .medium)).foregroundStyle(PostStyle.background).frame(width: 38, height: 38).background(PostStyle.accent, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.senderName).font(PostStyle.font(size: 14, weight: .semibold))
                    Text("\(message.senderAddress) · \(message.date.formatted(date: .abbreviated, time: .shortened))").font(PostStyle.font(size: 11)).foregroundStyle(PostStyle.secondary).textSelection(.enabled)
                    Text("To: \(message.to)").font(PostStyle.font(size: 10)).foregroundStyle(PostStyle.secondary).textSelection(.enabled)
                }
                Spacer()
                Menu {
                    Button("Reply") { store.newCompose(kind: "reply", replyingTo: message) }
                    Button("Reply all") { store.newCompose(kind: "replyAll", replyingTo: message) }
                    Button("Forward") { store.newCompose(kind: "forward", replyingTo: message) }
                    if !message.html.isEmpty { Button(useOriginalColors ? "Use app colors" : "Use original email colors") { originalColors = !useOriginalColors } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().pointerHover()
            }
            if !message.html.isEmpty && !plain {
                if !allowImages && !store.preferences.remoteImages {
                    HStack { Text("Remote images are blocked").font(PostStyle.font(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Load images") { allowImages = true }.controlSize(.small) }
                }
                HTMLMessage(html: message.html, remoteImages: allowImages || store.preferences.remoteImages, originalColors: useOriginalColors, foldQuotes: true, fontName: store.preferences.readingFont ?? "SF Pro Display", fontSize: store.preferences.readingSize ?? 15, onReady: { htmlReady = $0 })
                    .transaction { $0.animation = nil }.padding(.horizontal, 6).frame(minHeight: 100).clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                let parts = MessageQuote.split(message.body)
                Text(detectedLinks(parts.body)).font(.custom(store.preferences.readingFont ?? "SF Pro Display", size: store.preferences.readingSize ?? 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                if let quote = parts.quote {
                    DisclosureGroup("Quoted message", isExpanded: $showPlainQuote) {
                        Text(detectedLinks(quote)).font(PostStyle.font(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(PostStyle.font(size: 12)).padding(.horizontal, 6)
                }
            }
            let files = message.attachments.filter { $0.contentID == nil }
            ForEach(files) { attachment in
                Button { store.download(attachment, message: message) } label: {
                    HStack { Image(systemName: "paperclip"); Text(attachment.name); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)); Image(systemName: "arrow.down") }.font(PostStyle.font(size: 11)).padding(9).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(PostButtonStyle()).contextMenu { Button("Save attachment…") { store.download(attachment, message: message) } }
            }
            Button("Reply") { store.newCompose(kind: "reply", replyingTo: message) }.font(PostStyle.font(size: 12)).buttonStyle(PostButtonStyle())
        }
        .onAppear { if ready { onLayoutReady?() } }
        .onChange(of: htmlReady) { _, value in if value { onLayoutReady?() } }
        .opacity(ready ? 1 : 0)
        .allowsHitTesting(ready).accessibilityHidden(!ready)
        .transaction { $0.animation = nil }
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

private func detectedLinks(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
    for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""),
              let range = Range(match.range, in: text), let start = AttributedString.Index(range.lowerBound, within: result),
              let end = AttributedString.Index(range.upperBound, within: result) else { continue }
        result[start..<end].link = url
    }
    return result
}

struct HTMLMessage: View {
    let html: String
    let remoteImages: Bool
    var originalColors = true
    var foldQuotes = false
    var fontName = "SF Pro Display"
    var fontSize: Double = 15
    var onReady: ((Bool) -> Void)? = nil
    @LocalState private var height: CGFloat = 100
    var body: some View {
        HTMLDocument(html: html, remoteImages: remoteImages, originalColors: originalColors, foldQuotes: foldQuotes, fontName: fontName, fontSize: fontSize, onReady: onReady, height: $height)
            .frame(height: height)
            .background(originalColors ? Color.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HTMLDocument: NSViewRepresentable {
    static let webDataStore = WKWebsiteDataStore.nonPersistent()
    let html: String
    let remoteImages: Bool
    var originalColors = true
    var foldQuotes = false
    var fontName = "SF Pro Display"
    var fontSize: Double = 15
    var onReady: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Binding var height: CGFloat
    // Keep a bounded set of live documents, including their decoded images and layout.
    static var cacheLimit = 40
    static func clearRenderedCache() {
        let removable = rendered.filter { $0.view.superview == nil }
        rendered.removeAll { $0.view.superview == nil }
        for entry in removable { entry.view.stopLoading(); entry.view.configuration.userContentController.removeScriptMessageHandler(forName: "postHeight"); entry.view.configuration.userContentController.removeScriptMessageHandler(forName: "postReady") }
    }
    private static var rendered: [(key: String, view: WKWebView, coordinator: Coordinator)] = []
    private var renderKey: String { html + String(remoteImages) + String(colorScheme == .dark) + String(originalColors) + String(foldQuotes) + fontName + String(fontSize) }
    func makeCoordinator() -> Coordinator {
        if let entry = Self.rendered.first(where: { $0.key == renderKey && $0.view.superview == nil }) { return entry.coordinator }
        return Coordinator()
    }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.setHeight = nil
        coordinator.onReady = nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: context.coordinator.measuredHeight ?? height)
    }
    func makeNSView(context: Context) -> WKWebView {
        if let index = Self.rendered.firstIndex(where: { $0.key == renderKey && $0.coordinator === context.coordinator }) {
            let entry = Self.rendered.remove(at: index)
            Self.rendered.append(entry)
            return entry.view
        }
        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: """
        const generation = document.documentElement.dataset.postRender;
        // Measure content independently of WebKit's viewport, which can retain an old height.
        const content = document.createElement('div'); content.id = 'post-mail-content';
        content.style.cssText = 'display:flow-root!important;height:auto!important;min-height:0!important;max-height:none!important;padding:20px 24px!important;box-sizing:border-box!important';
        while (document.body.firstChild) content.append(document.body.firstChild);
        document.body.append(content);
        document.body.style.setProperty('height', 'auto', 'important');
        document.body.style.setProperty('min-height', '0', 'important');
        document.body.style.setProperty('padding', '0', 'important');
        const measure = () => window.webkit.messageHandlers.postHeight.postMessage({ generation, height: content.getBoundingClientRect().height });
        const blank = node => node.nodeType === Node.TEXT_NODE ? !node.textContent.trim() :
            node.nodeType === Node.ELEMENT_NODE && (node.tagName === 'BR' ||
            (!node.textContent.trim() && !node.querySelector('img,svg,table,hr,input,details') && !node.matches('img,svg,table,hr,input,details')));
        const trimEnd = node => {
            while (node.lastChild && blank(node.lastChild)) node.lastChild.remove();
            const last = node.lastElementChild;
            if (last && ['DIV','SECTION'].includes(last.tagName)) trimEnd(last);
        };
        if (\(foldQuotes)) {
            const candidates = [...document.querySelectorAll('.gmail_quote, .yahoo_quoted, blockquote, #divRplyFwdMsg')];
            candidates.filter(node => !candidates.some(other => other !== node && other.contains(node))).forEach(node => {
                const details = document.createElement('details'); details.className = 'post-quote';
                const summary = document.createElement('summary'); summary.textContent = 'Quoted message';
                node.before(details); details.append(summary);
                if (node.id === 'divRplyFwdMsg') {
                    while (details.nextSibling) details.append(details.nextSibling);
                } else { details.append(node); }
                while (details.previousSibling && blank(details.previousSibling)) details.previousSibling.remove();
                details.addEventListener('toggle', measure);
            });
        }
        trimEnd(content);
        new ResizeObserver(measure).observe(content); measure();
        requestAnimationFrame(() => requestAnimationFrame(() => {
            window.webkit.messageHandlers.postReady.postMessage({ generation, height: content.getBoundingClientRect().height });
        }));
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.addUserScript(WKUserScript(source: #"""
        // Linkify text nodes only; never change existing links, attributes, or styles.
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        const nodes = [];
        while (walker.nextNode()) {
            const node = walker.currentNode;
            if (!node.parentElement.closest('a,script,style,textarea,code,pre')) nodes.push(node);
        }
        for (const node of nodes) {
            const text = node.textContent;
            const pattern = /(?:https?:\/\/|www\.)[^\s<>"']+/gi;
            const fragment = document.createDocumentFragment();
            let end = 0, found = false;
            for (const match of text.matchAll(pattern)) {
                let address = match[0].replace(/[.,;!?:]+$/, '');
                while (address.endsWith(')') && (address.match(/\)/g) || []).length > (address.match(/\(/g) || []).length) address = address.slice(0, -1);
                const href = /^www\./i.test(address) ? 'https://' + address : address;
                try { if (!['http:', 'https:'].includes(new URL(href).protocol)) continue; } catch { continue; }
                fragment.append(document.createTextNode(text.slice(end, match.index)));
                const anchor = document.createElement('a'); anchor.href = href; anchor.textContent = address;
                fragment.append(anchor); end = match.index + address.length; found = true;
            }
            if (found) { fragment.append(document.createTextNode(text.slice(end))); node.replaceWith(fragment); }
        }
        """#, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "postHeight")
        config.userContentController.add(context.coordinator, name: "postReady")
        config.websiteDataStore = Self.webDataStore;
        config.setURLSchemeHandler(PostImageLoader.shared, forURLScheme: "post-image"); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = ThreadWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; view.setValue(false, forKey: "drawsBackground")
        Self.rendered.append((renderKey, view, context.coordinator))
        while Self.rendered.count > Self.cacheLimit {
            guard let index = Self.rendered.firstIndex(where: { $0.view.superview == nil && $0.view !== view }) else { break }
            let removed = Self.rendered.remove(at: index)
            removed.view.configuration.userContentController.removeScriptMessageHandler(forName: "postHeight")
            removed.view.configuration.userContentController.removeScriptMessageHandler(forName: "postReady")
            removed.view.stopLoading()
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.setHeight = { value in if abs(height - value) > 1 { height = value } }
        let signature = renderKey
        guard context.coordinator.signature != signature else {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                if let measured = coordinator.measuredHeight { coordinator.setHeight?(measured) }
                coordinator.onReady?(coordinator.isReady)
            }
            return
        }
        context.coordinator.signature = signature
        context.coordinator.isReady = false
        context.coordinator.measuredHeight = nil
        if let index = Self.rendered.firstIndex(where: { $0.view === view }) { Self.rendered[index].key = signature }
        let generation = UUID().uuidString
        context.coordinator.generation = generation
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            guard coordinator?.generation == generation else { return }
            coordinator?.onReady?(false)
        }
        let images = remoteImages ? "post-image: data: cid:" : "data: cid:"
        let renderedHTML = remoteImages ? MessageHTML.cachedImageURLs(html) : html
        let dark = colorScheme == .dark && !originalColors
        let colors = originalColors ? "" : "body{background:transparent!important;color:\(dark ? "#e5eaf1" : "#242a34")!important}body *{font-family:inherit!important;color:inherit!important;-webkit-text-fill-color:currentColor!important}p,span,td,th,div,li,table,h1,h2,h3,h4,h5,h6{background-color:transparent!important}p,span,td,li{font-size:inherit!important}a,a *{color:\(dark ? "#9ecafa" : "#176edc")!important}"
        let document = "<!doctype html><html data-post-render='\(generation)'><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src \(images); style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'\"><style>body{background:white;font:\(fontSize)px \(MIMEBuilder.htmlEscape(fontName)),sans-serif;color:#242a34;margin:0;padding:20px 24px;box-sizing:border-box;line-height:1.65;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}a{color:#176edc}html{overflow:hidden}details.post-quote{margin-top:14px}details.post-quote>summary{cursor:pointer;font-size:12px;color:#7d8b9c;user-select:none}details.post-quote[open]>summary{margin-bottom:12px}\(colors)</style></head><body>\(renderedHTML)</body></html>"
        context.coordinator.navigation = view.loadHTMLString(document, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var signature = ""
        var measuredHeight: CGFloat?
        var isReady = false
        var setHeight: ((CGFloat) -> Void)?
        var onReady: ((Bool) -> Void)?
        var generation = ""
        var navigation: WKNavigation?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let payload = message.body as? [String: Any],
                  let token = payload["generation"] as? String, token == generation,
                  let number = payload["height"] as? NSNumber else { return }
            let value = min(max(CGFloat(number.doubleValue), 100), 30000)
            let ready = message.name == "postReady"
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.measuredHeight = value
                self.setHeight?(value)
                if ready { self.isReady = true; self.onReady?(true) }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation else { return }
            let token = generation
            webView.evaluateJavaScript("document.getElementById('post-mail-content')?.getBoundingClientRect().height") { value, _ in
                guard self.generation == token, let number = value as? NSNumber else { return }
                self.measuredHeight = min(max(CGFloat(number.doubleValue), 100), 30000)
                self.setHeight?(self.measuredHeight!)
                self.isReady = true
                self.onReady?(true)
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
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    @LocalState private var labelAndArchive = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Apply label").font(PostStyle.font(size: 20, weight: .bold)); Spacer(); Button("Done") { store.showLabels = false } }
            Toggle("Skip the inbox when applying a label", isOn: $labelAndArchive).font(PostStyle.font(size: 12))
            ScrollView { VStack(spacing: 5) { ForEach(store.folders.filter(\.isCustom)) { folder in
                let targets = store.messages.filter { store.actionIDs.contains($0.id) }; let applied = !targets.isEmpty && targets.allSatisfy { $0.labels.contains(folder.id) }
                Button { if applied { store.actOnSelected(add: [], remove: [folder.id]) } else { store.actOnSelected(add: [folder.id], remove: labelAndArchive ? ["INBOX"] : [], advance: labelAndArchive) }; store.showLabels = false } label: { HStack { Image(systemName: folder.icon.replacingOccurrences(of: "circle", with: "square")); Text(folder.name); Spacer(); if applied { Image(systemName: "checkmark") } }.padding(11).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(PostButtonStyle())
            } } }
            if store.folders.filter(\.isCustom).isEmpty { Text("Create a label using the + button in the sidebar.").foregroundStyle(.secondary) }
        }.padding(24).frame(width: 430, height: 360)
    }
}

struct ComposePane: View {
    @ObservedObject private var palette = PostPalette.shared
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
    @LocalState private var bodyEditor: NSTextView?
    @LocalState private var composeFont = "SF Pro Display"
    @LocalState private var composeSize: Double = 14
    @LocalState private var composeColor = "default"
    @LocalState private var composeSpacing: Double = 3
    @LocalState private var showSchedule = false
    @LocalState private var scheduleDate = Date().addingTimeInterval(3600)
    init(initial: ComposeDraft, embedded: Bool = false) {
        self.initial = initial; self.embedded = embedded
        var value = initial; value.separateLegacyQuote()
        self.baseline = value
        _draft = LocalState(initialValue: value)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(draft.quotedText == nil ? "Compose" : "Reply").font(PostStyle.font(size: 18, weight: .semibold)); Spacer(); if sending { ProgressView().controlSize(.small) }; Button("Save & close") { saveAndClose() }.disabled(sending); Button("Send") { sending = true; Task { if await store.send(draft) { closeEditor() }; sending = false } }.buttonStyle(.borderedProminent).disabled(sending || draft.to.isEmpty || !store.connected); Button { showSchedule = true } label: { Image(systemName: "clock") }.help("Send later").popover(isPresented: $showSchedule, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { schedulePopover }.disabled(sending || draft.to.isEmpty || (!store.connected && !store.demoMode)) ; Button { confirmDelete = true } label: { Image(systemName: "trash") }.help("Delete draft").disabled(sending) }.padding(20)
            Divider()
            HStack { Text("To").frame(width: 65, alignment: .leading).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary); TextField("", text: $draft.to).accessibilityLabel("To").textFieldStyle(.plain); Button("Cc/Bcc") { showCC.toggle() }.buttonStyle(PostButtonStyle()).font(PostStyle.font(size: 11)).foregroundStyle(.secondary) }.padding(.horizontal, 22).padding(.vertical, 12)
            if showCC || !draft.cc.isEmpty || !draft.bcc.isEmpty { recipientRow("Cc", text: $draft.cc); recipientRow("Bcc", text: $draft.bcc) }
            Divider().padding(.horizontal, 22)
            HStack { Text("Subject").frame(width: 65, alignment: .leading).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary); SubjectInput(text: $draft.subject, onTab: focusBodyStart).frame(height: 22) }.padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    composerFormatting
                    RichComposer(text: $draft.body, richData: $draft.richBody, fontName: composeFont, size: composeSize, color: composerNSColor, spacing: composeSpacing, editor: $bodyEditor, focusOnLoad: !draft.to.isEmpty).frame(minHeight: draft.quotedText == nil ? 280 : 170)
                    if let quote = draft.quotedText {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text(draft.quoteHeading ?? "Previous message").font(PostStyle.font(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Remove quote") { draft.quotedText = nil; draft.quotedHTML = nil; draft.quoteHeading = nil; scheduleSave() }.font(PostStyle.font(size: 10)) }
                            HStack(alignment: .top, spacing: 16) {
                                RoundedRectangle(cornerRadius: 1).fill(PostStyle.accent.opacity(0.25)).frame(width: 2)
                                if let html = draft.quotedHTML, !html.isEmpty { HTMLMessage(html: html, remoteImages: false).frame(minHeight: 330) }
                                else { Text(detectedLinks(quote)).font(PostStyle.font(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }.padding(16).background(PostStyle.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .contextMenu { Button("Copy quoted message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(quote, forType: .string) }; Button("Remove quote") { draft.quotedText = nil; draft.quotedHTML = nil; draft.quoteHeading = nil; scheduleSave() } }
                    }
                }.padding(20)
            }
            if !draft.attachments.isEmpty { ScrollView(.horizontal) { HStack { ForEach(draft.attachments) { attachment in HStack { Image(systemName: "paperclip"); Text(attachment.name).lineLimit(1); Button { draft.attachments.removeAll { $0.id == attachment.id }; scheduleSave() } label: { Image(systemName: "xmark") }.buttonStyle(PostButtonStyle()) }.font(PostStyle.font(size: 11)).padding(8).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 5)) } }.padding(.horizontal, 18) }.frame(height: 42) }
            Divider()
            HStack { Button { attach() } label: { Label("Attach files", systemImage: "paperclip") }; Spacer(); Text(store.connected ? "Drafts save automatically" : "Preview • sending is unavailable").font(PostStyle.font(size: 11)).foregroundStyle(.secondary) }.padding(16)
        }.animation(.easeInOut(duration: 0.22), value: showCC).buttonStyle(PostButtonStyle()).frame(width: embedded ? nil : 760, height: embedded ? nil : 620).frame(maxWidth: .infinity, maxHeight: .infinity).background(PostStyle.background).preferredColorScheme(PostStyle.scheme(store.preferences.appearance)).interactiveDismissDisabled(true)
        .onAppear { composeFont = store.preferences.composerFont ?? "SF Pro Display"; composeSize = store.preferences.composerSize ?? 14; composeColor = store.preferences.composerColor ?? "default"; composeSpacing = store.preferences.composerSpacing ?? 3; if let rich = draft.richBody, let text = try? NSAttributedString(data: rich, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), text.length > 0, let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont { composeFont = font.familyName ?? composeFont; composeSize = font.pointSize }; if !initialized { existedAtOpen = store.drafts.contains { $0.id == draft.id }; initialized = true; if !embedded && !draft.to.isEmpty { DispatchQueue.main.async { focusBodyStart(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.setSelectedRange(NSRange(location: 0, length: 0)); editor.scrollRangeToVisible(NSRange(location: 0, length: 0)) } } } } } }
        .onChange(of: bodyEditor != nil) { _, ready in if ready && !draft.to.isEmpty { focusBodyStart() } }
        .onChange(of: store.composerDismissRequest) { _, _ in requestDismiss() }
        .postPrompt("Save draft?", isPresented: $showDismissPrompt, message: "Save your changes before closing?", actions: ["Save", "Keep writing", "Discard changes"]) { response in
            if response == 0 { saveAndClose() }
            else if response == 2 { discardAndClose() }
            else { scheduleSave() }
        }
        .postPrompt("Delete draft?", isPresented: $confirmDelete, message: "This deletes the draft from Post and Gmail if it has been synced.", actions: ["Delete", "Cancel"]) { response in
            if response == 0 { autosave?.cancel(); skipFinalSave = true; store.deleteDraft(draft); closeEditor() }
        }
        .onChange(of: draft.richBody) { _, _ in scheduleSave() }
        .onChange(of: draft.cc) { _, _ in scheduleSave() }.onChange(of: draft.bcc) { _, _ in scheduleSave() }
        .onChange(of: draft.to) { _, _ in scheduleSave() }.onChange(of: draft.subject) { _, _ in scheduleSave() }.onChange(of: draft.body) { _, _ in scheduleSave() }
        .onDisappear { autosave?.cancel(); if !skipFinalSave && !store.discardedDraftIDs.contains(draft.id) && (existedAtOpen || draft.hasUserChanges(from: baseline)) { store.saveDraft(draft, sync: false) } }
    }
    private var composerNSColor: NSColor {
        switch composeColor { case "blue": return .systemBlue; case "gray": return .systemGray; case "red": return .systemRed; default: return NSColor(postHex: composeColor) ?? .textColor }
    }
    private func focusBodyStart() {
        DispatchQueue.main.async {
            guard let bodyEditor else { return }
            bodyEditor.window?.makeFirstResponder(bodyEditor)
            bodyEditor.setSelectedRange(NSRange(location: 0, length: 0)); bodyEditor.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }
    private var schedulePopover: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Send later").font(PostStyle.font(size: 13, weight: .semibold))
                DatePicker("Send at", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Text("Post sends while running. Overdue mail sends after reopening.").font(PostStyle.font(size: 11)).foregroundStyle(.secondary)
                HStack { Button("Cancel") { showSchedule = false }; Button("Schedule") { if store.queueSend(draft, at: scheduleDate) { showSchedule = false; closeEditor() } }.buttonStyle(.borderedProminent) }
            }.padding(22).frame(width: 400)
    }
    private func formatUnderline() { bodyEditor?.postToggleUnderline() }
    private func formatTrait(_ trait: NSFontTraitMask) { bodyEditor?.postToggleTrait(trait) }
    private var composerFormatting: some View {
        HStack(spacing: 8) {
            Picker("Font", selection: $composeFont) { ForEach(FontChoices.names, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 155)
            Picker("Size", selection: $composeSize) { ForEach([12.0,14,16,18,20,24], id: \.self) { Text(String(Int($0))).tag($0) } }.labelsHidden().frame(width: 80)
            Button { formatTrait(.boldFontMask) } label: { Image(systemName: "bold") }.help("Bold")
            Button { formatTrait(.italicFontMask) } label: { Image(systemName: "italic") }.help("Italic")
            Button { formatUnderline() } label: { Image(systemName: "underline") }.help("Underline")
            ColorPicker("Text color", selection: Binding(get: { Color(nsColor: composerNSColor) }, set: { composeColor = NSColor($0).postHex }), supportsOpacity: false).labelsHidden().frame(width: 28)
            Menu { Button("Align left") { bodyEditor?.alignLeft(nil) }; Button("Center") { bodyEditor?.alignCenter(nil) }; Button("Align right") { bodyEditor?.alignRight(nil) } } label: { Image(systemName: "text.alignleft") }.fixedSize()
            Spacer()
        }.controlSize(.small)
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

struct PointerHover: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.background(PointerCursorRegion(enabled: enabled))
    }
}
private struct PointerCursorRegion: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        if view.enabled != enabled {
            view.enabled = enabled
            view.window?.invalidateCursorRects(for: view)
        }
    }
    final class CursorView: NSView {
        var enabled = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            // Let AppKit restore the cursor after menus, drags and window changes.
            // Restrict it to the visible area, including clipped sidebar rows.
            if enabled && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty {
                addCursorRect(visibleRect, cursor: .pointingHand)
            }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
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
    @ObservedObject private var palette = PostPalette.shared
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
            if Bundle.main.bundleIdentifier == "com.jack.Post.demo" {
                window.setContentSize(NSSize(width: 1670, height: 920))
                window.center()
            }
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
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.stack").font(PostStyle.font(size: 32, weight: .light)).foregroundStyle(PostStyle.accent)
            Text("\(store.bulkIDs.count) \(store.folderID == "DRAFT" ? "drafts" : "messages") selected").font(PostStyle.font(size: 20, weight: .medium))
            if store.folderID == "DRAFT" {
                Button { store.perform("trash") } label: { Label("Delete drafts", systemImage: "trash") }.buttonStyle(PostButtonStyle())
            } else {
            HStack(spacing: 14) {
                Button { store.showLabels = true } label: { Label("Move to label", systemImage: "tag") }
                Button { store.actOnSelected(add: [], remove: ["INBOX"], advance: true) } label: { Label("Archive", systemImage: "archivebox") }
                Button { store.actOnSelected(add: ["TRASH"], remove: ["INBOX"], advance: true) } label: { Label("Trash", systemImage: "trash") }
            }.buttonStyle(PostButtonStyle()).font(PostStyle.font(size: 12))
            }
            Text("Shift-click to select a range. Command-click to add or remove a message.").font(PostStyle.font(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Clear selection") { store.select(nil) }.font(PostStyle.font(size: 11))
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
    private var mode = "balanced"
    private var root: URL?
    private var cache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024, diskPath: "Post-RemoteImages")
    private lazy var session: URLSession = makeSession()
    private var downloads: [URL: URLSessionDataTask] = [:]
    private var waiting: [URL: [ObjectIdentifier: WKURLSchemeTask]] = [:]
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = cache; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20; config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }
    func configure(mode: String, directory: URL) {
        guard self.mode != mode || root != directory else { return }
        self.mode = mode; root = directory
        cache = URLCache(memoryCapacity: (mode == "fast" ? 128 : 32) * 1024 * 1024, diskCapacity: (mode == "fast" ? 1024 : 128) * 1024 * 1024, directory: directory.appendingPathComponent("RemoteImages"))
        session.finishTasksAndInvalidate(); session = makeSession()
    }
    func clear() { cache.removeAllCachedResponses() }
    func prefetch(_ html: String) {
        guard mode == "fast", let regex = try? NSRegularExpression(pattern: #"(?:src|background)=["'](https?://[^"']+)"#, options: [.caseInsensitive]) else { return }
        let text = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)).prefix(12) {
            guard let url = URL(string: text.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")) else { continue }
            fetch(url)
        }
    }
    private func fetch(_ original: URL) {
        guard downloads[original] == nil else { return }
        var request = URLRequest(url: original)
        request.cachePolicy = mode == "fast" ? .returnCacheDataElseLoad : .useProtocolCachePolicy
        downloads[original] = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.downloads.removeValue(forKey: original)
                let listeners = self.waiting.removeValue(forKey: original) ?? [:]
                for task in listeners.values {
                    if let error { task.didFailWithError(error); continue }
                    guard let data, let response, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true, let url = task.request.url else { task.didFailWithError(URLError(.badServerResponse)); continue }
                    task.didReceive(URLResponse(url: url, mimeType: response.mimeType, expectedContentLength: data.count, textEncodingName: response.textEncodingName))
                    task.didReceive(data); task.didFinish()
                }
            }
        }
        downloads[original]?.resume()
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let original = MessageHTML.originalImageURL(url) else { task.didFailWithError(URLError(.badURL)); return }
        waiting[original, default: [:]][ObjectIdentifier(task)] = task
        fetch(original)
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        guard let url = task.request.url, let original = MessageHTML.originalImageURL(url) else { return }
        waiting[original]?.removeValue(forKey: ObjectIdentifier(task))
        if waiting[original]?.isEmpty == true { waiting.removeValue(forKey: original) }
        // Keep the shared download alive for nearby messages and the disk cache.
    }
}
