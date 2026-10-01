import SwiftUI
import AppKit

struct FontChoices {
    static var names: [String] { ["Helvetica Neue", "Arial", "Avenir Next", "Georgia", "Menlo", "Times New Roman"] + NSFontManager.shared.availableFontFamilies.filter { !["Helvetica Neue", "Arial", "Avenir Next", "Georgia", "Menlo", "Times New Roman"].contains($0) }.sorted() }
}
struct FlowLabelChips: View {
    @ObservedObject private var palette = PostPalette.shared
    let labels: [MailFolder]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(labels) { label in Text(label.name).font(.system(size: 10, weight: .medium)).foregroundStyle(PostStyle.accent).padding(.horizontal, 8).padding(.vertical, 4).background(PostStyle.selection, in: RoundedRectangle(cornerRadius: 5)) } } }
    }
}

struct SettingsPane: View {
    @ObservedObject private var palette = PostPalette.shared
    @EnvironmentObject var store: MailStore
    @LocalState private var section = "Appearance"
    @LocalState private var cacheSize = ""
    @LocalState private var clearMediaPrompt = false
    private let sections = [("Appearance", "paintbrush"), ("Inbox", "tray"), ("Sidebar", "sidebar.left"), ("Reading", "doc.text"), ("Composing", "square.and.pencil"), ("Sending", "paperplane"), ("Notifications", "bell"), ("Shortcuts", "keyboard"), ("Storage & downloads", "externaldrive"), ("Account", "person.crop.square")]
    private func option<T>(_ key: WritableKeyPath<MailPreferences, T?>, _ fallback: T) -> Binding<T> { Binding(get: { store.preferences[keyPath: key] ?? fallback }, set: { store.preferences[keyPath: key] = $0 }) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Settings").font(.system(size: 16, weight: .semibold)).padding(.bottom, 16)
                ForEach(sections, id: \.0) { name, icon in
                    Button { section = name } label: { Label(name, systemImage: icon).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(section == name ? PostStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(PostButtonStyle(selected: section == name))
                }
                Spacer(); Button("Done") { store.showSettings = false }.keyboardShortcut(.defaultAction)
            }.padding(18).frame(width: 205).background(PostStyle.sidebar)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(section).font(.system(size: 25, weight: .semibold))
                    content
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
            }
        }.buttonStyle(PostButtonStyle()).tint(PostStyle.accent).frame(width: 810, height: 730).background(PostStyle.background).preferredColorScheme(PostStyle.scheme(store.preferences.appearance))
        .onAppear { store.refreshNotificationStatus(); updateCacheSize() }
        .onDisappear { store.recordingShortcut = nil }
        .postPrompt("Clear downloaded media?", isPresented: $clearMediaPrompt, message: "Messages, drafts, attachments saved to Downloads, and settings stay on this Mac. Cached images and attachment downloads will load again when needed.", actions: ["Clear", "Cancel"]) { response in
            if response == 0 { store.clearDownloadedMedia(); PostImageLoader.shared.clear(); HTMLDocument.clearRenderedCache(); updateCacheSize() }
        }
    }
    @ViewBuilder private var content: some View {
        switch section {
        case "Appearance":
            Picker("Appearance", selection: option(\.appearance, "system")) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
            Picker("Accent color", selection: option(\.accentColor, "blue")) { ForEach(["blue", "purple", "green", "orange", "pink", "gray", "custom"], id: \.self) { Text($0.capitalized).tag($0) } }
            if store.preferences.accentColor == "custom" {
                ColorPicker("Custom accent", selection: Binding(get: { Color(nsColor: NSColor(postHex: store.preferences.accentHex ?? "3B6EA3") ?? .systemBlue) }, set: { store.preferences.accentHex = NSColor($0).postHex }), supportsOpacity: false)
            }
            GroupBox("Message list") { VStack(alignment: .leading, spacing: 14) {
                Picker("Text size", selection: option(\.listSize, 14)) { ForEach([12.0, 14, 16, 18], id: \.self) { Text("\(Int($0)) pt").tag($0) } }
                Picker("Density", selection: option(\.listDensity, "standard")) { Text("Compact").tag("compact"); Text("Standard").tag("standard"); Text("Spacious").tag("spacious") }
                Toggle("Use bold text for unread messages", isOn: option(\.boldUnread, true))
            }.padding(8) }
        case "Inbox":
            Picker("Primary view", selection: Binding(get: { store.preferences.primaryMode ?? "wide" }, set: { store.preferences.primaryMode = $0; store.primarySettingsChanged() })) { Text("Gmail Primary category").tag("gmail"); Text("All inbox categories").tag("wide") }
            Text("Labels included in Primary").font(.headline)
            Text("Unlabeled inbox mail is included. New labels are excluded until enabled.").font(.caption).foregroundStyle(.secondary)
            ForEach(store.primaryLabelChoices) { label in Toggle(label.name, isOn: Binding(get: { store.primaryIncludedLabels.contains(label.id) }, set: { store.setPrimaryLabel(label.id, included: $0) })) }
        case "Sidebar":
            Toggle("Show numbered badges", isOn: option(\.sidebarBadges, true))
            Picker("Sidebar counts", selection: $store.preferences.totalCounts) { Text("Unread").tag(false); Text("Total").tag(true) }.pickerStyle(.segmented)
            Text("Label order and visibility").font(.headline)
            Text("Drag a handle to reorder. Primary stays first. Hidden labels stay in Gmail.").font(.caption).foregroundStyle(.secondary)
            ForEach(store.orderedSidebarLabels.filter { $0.id != "primary" }) { label in
                HStack {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 28, height: 30).contentShape(Rectangle()).background(MailDragSurface(payload: "post-label:" + label.id, title: label.name)).help("Drag to reorder")
                    Toggle(label.name, isOn: Binding(get: { !(store.preferences.hiddenSidebarLabels ?? []).contains(label.id) }, set: { store.setSidebarLabel(label.id, visible: $0) }))
                }.padding(9).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 8))
                    .onDrop(of: [.text], isTargeted: nil) { providers, location in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let text = value as? String, text.hasPrefix("post-label:") else { return }
                            Task { @MainActor in _ = store.reorderSidebarLabel(String(text.dropFirst(11)), before: label.id, after: location.y > 24) }
                        }; return true
                    }
            }
        case "Reading":
            Toggle("Group messages into conversations", isOn: option(\.groupConversations, true))
            Toggle("Mark opened messages as read", isOn: $store.preferences.markRead)
            Picker("Mark as read after", selection: option(\.readDelay, 0)) { Text("Immediately").tag(0); ForEach([1, 3, 5, 10, 30], id: \.self) { Text("\($0) seconds").tag($0) } }.disabled(!store.preferences.markRead)
            fontPicker("Reading font", selection: option(\.readingFont, "Helvetica Neue"))
            Picker("Reading text size", selection: option(\.readingSize, 15)) { ForEach([12.0,14,15,16,18,20,24], id: \.self) { Text("\(Int($0)) pt").tag($0) } }
            Toggle("Load remote images automatically", isOn: $store.preferences.remoteImages)
        case "Composing":
            fontPicker("Default font", selection: option(\.composerFont, "Helvetica Neue"))
            Picker("Default text size", selection: option(\.composerSize, 14)) { ForEach([12.0,14,16,18,20,24], id: \.self) { Text("\(Int($0)) pt").tag($0) } }
            Picker("Text color", selection: option(\.composerColor, "default")) { Text("Default").tag("default"); Text("Blue").tag("blue"); Text("Gray").tag("gray"); Text("Red").tag("red"); if let value = store.preferences.composerColor, NSColor(postHex: value) != nil { Text("Custom").tag(value) } }
            ColorPicker("Custom text color", selection: Binding(get: { Color(nsColor: NSColor(postHex: store.preferences.composerColor ?? "000000") ?? .textColor) }, set: { store.preferences.composerColor = NSColor($0).postHex }), supportsOpacity: false)
            Picker("Line spacing", selection: option(\.composerSpacing, 3)) { Text("Tight").tag(0.0); Text("Standard").tag(3.0); Text("Relaxed").tag(6.0) }
            Text("Formatting controls are also available in each composer.").font(.caption).foregroundStyle(.secondary)
            Text("Signature").font(.headline)
            TextEditor(text: $store.preferences.signature).font(.system(size: 12)).frame(height: 120).padding(8).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 8))
        case "Sending":
            Picker("Undo Send delay", selection: option(\.undoSendDelay, 5)) { Text("Off").tag(0); ForEach([5,10,20,30], id: \.self) { Text("\($0) seconds").tag($0) } }
            Text("Send waits for this delay. Undo Send returns the message to the composer.").font(.caption).foregroundStyle(.secondary)
            Text("Scheduled sending").font(.headline)
            Text("Choose Send later in the composer. Queued mail stays on this Mac and appears in Drafts. Opening a queued draft cancels its schedule. Post must be running; overdue mail sends after reopening.").font(.system(size: 12)).foregroundStyle(.secondary)
        case "Notifications":
            Toggle("Show new-mail notifications", isOn: $store.preferences.notifications).onChange(of: store.preferences.notifications) { _, value in if value { store.enableNotifications() } }
            Picker("Notify me about", selection: option(\.notificationScope, "primary")) { Text("Primary inbox").tag("primary"); Text("All mail").tag("all"); Text("Selected labels").tag("labels") }
            if store.preferences.notificationScope == "labels" {
                ForEach(store.primaryLabelChoices) { label in Toggle(label.name, isOn: Binding(get: { (store.preferences.notificationLabels ?? []).contains(label.id) }, set: { enabled in var ids = store.preferences.notificationLabels ?? []; if enabled { ids.insert(label.id) } else { ids.remove(label.id) }; store.preferences.notificationLabels = ids })) }
            }
            TextField("Sender allowlist, separated by commas", text: option(\.notificationSenders, ""))
            Text("Leave the allowlist empty for all senders. Spam and Trash never notify.").font(.caption).foregroundStyle(.secondary)
            Toggle("Quiet hours", isOn: option(\.quietHours, false))
            if store.preferences.quietHours == true {
                HStack { Picker("From", selection: option(\.quietStart, 22)) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }; Picker("Until", selection: option(\.quietEnd, 8)) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } } }
            }
            Toggle("Play a sound", isOn: option(\.notificationSound, true))
            Toggle("Show sender", isOn: option(\.showNotificationSender, true))
            Toggle("Show subject", isOn: option(\.showNotificationSubject, true))
            Toggle("Show message excerpt", isOn: option(\.showNotificationBody, false))
            Toggle("Show banners while Post is active", isOn: option(\.notificationForeground, false))
            Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            Text(store.notificationTestStatus).font(.caption).foregroundStyle(.secondary)
            HStack { Button("Test notification") { store.testNotification() }; Button("macOS notification settings") { store.openNotificationSettings() } }
            Text("Post checks every minute while running. Quiet-hour messages do not generate delayed banners.").font(.caption).foregroundStyle(.secondary)
        case "Shortcuts":
            Toggle("Show shortcut hints below the message panes", isOn: option(\.showShortcutHints, true))
            Text("Record a shortcut. Menus and hints update immediately.").font(.caption).foregroundStyle(.secondary)
            ForEach(Shortcut.names, id: \.0) { action, name in shortcutRow(name, key: action, shortcut: store.preferences.shortcuts[action]) }
            Text("Label navigation").font(.headline)
            Text("Command shortcuts work with no selected message, composer, or text field. Hold Command to see each label’s key.").font(.caption).foregroundStyle(.secondary)
            ForEach(store.sidebarLabels) { label in shortcutRow(label.name, key: "label:" + label.id, shortcut: store.shortcutLabels().first { $0.0.id == label.id }?.1) }
            Button("Restore shortcut defaults") { store.preferences.shortcuts = Shortcut.defaults; store.preferences.labelShortcuts = nil; store.recordingShortcut = nil }
        case "Storage & downloads":
            Picker("Cache mode", selection: option(\.cacheMode, "balanced")) { Text("Balanced (default)").tag("balanced"); Text("Faster, more storage").tag("fast") }
            Text("Balanced keeps up to 40 rendered emails and a 128 MB image cache. Faster keeps up to 120 rendered emails, a 1 GB image cache, preloads nearby conversations, and caches up to 20 MB of attachments per opened thread.").font(.caption).foregroundStyle(.secondary)
            Text("Local mail and media: " + cacheSize).font(.system(size: 12))
            HStack { Button("Refresh size") { updateCacheSize() }; Button("Clear downloaded media…") { clearMediaPrompt = true } }
            Text("Messages and drafts remain available offline in both modes. Faster mode uses more memory and Gmail requests.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Attachment download location").font(.headline)
            Text(store.downloadDirectory.path).font(.caption).textSelection(.enabled)
            HStack { Button("Choose folder…") { store.chooseDownloadDirectory() }; Button("Use Downloads") { store.preferences.downloadDirectory = nil }; Button("Show in Finder") { NSWorkspace.shared.open(store.downloadDirectory) } }
        default:
            Text(store.connected ? store.account : "No Gmail account connected").font(.headline).textSelection(.enabled)
            if store.connected { Button("Disconnect Gmail") { store.disconnect() } }
            else {
                Text("Import your Google Desktop OAuth client, then sign in using your browser.").font(.caption)
                Button(store.hasClient ? "Replace Google client…" : "Import Google client…") { store.importOAuth() }
                Button("Sign in with Google") { store.signIn() }.buttonStyle(.borderedProminent).disabled(!store.hasClient || store.busy)
                Button("Open setup guide") { if let url = Bundle.main.url(forResource: "Setup", withExtension: "md") { NSWorkspace.shared.open(url) } }
            }
            Text("Sign-in stays in macOS Keychain. Cached mail and drafts stay on this Mac.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func fontPicker(_ title: String, selection: Binding<String>) -> some View { Picker(title, selection: selection) { ForEach(FontChoices.names, id: \.self) { Text($0).tag($0) } } }
    private func shortcutRow(_ title: String, key: String, shortcut: Shortcut?) -> some View {
        HStack { Text(title).font(.system(size: 12)); Spacer(); Text(shortcut?.display ?? "").font(.system(size: 11, weight: .medium)).padding(6).background(PostStyle.subtle, in: RoundedRectangle(cornerRadius: 5)); Button(store.recordingShortcut == key ? "Press keys…" : "Record") { store.recordingShortcut = key }.font(.system(size: 11)) }
    }
    private func updateCacheSize() { cacheSize = ByteCountFormatter.string(fromByteCount: store.cacheBytes, countStyle: .file) }
}
