import SwiftUI
import AppKit
import UserNotifications

@main
struct PostApp: App {
    @StateObject private var store = MailStore()
    @NSApplicationDelegateAdaptor(PostDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Post") {
            MailWindow().environmentObject(store)
                .onAppear { delegate.connect(store); store.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1370, height: 860)
        .commands {
            CommandGroup(after: .appInfo) { Button("Check for updates…") { PostUpdates.shared.openAccount = true; store.showSettings = true; Task { await PostUpdates.shared.check() } } }
            CommandGroup(after: .toolbar) {
                Menu("Appearance") {
                    ForEach(["system", "light", "dark"], id: \.self) { value in
                        Button(value.capitalized) { store.preferences.appearance = value }
                    }
                }
            }
            CommandGroup(replacing: .newItem) { action("Compose", "compose") }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { store.showSettings = true }.keyboardShortcut(",", modifiers: .command) }
            CommandGroup(replacing: .undoRedo) { Button("Undo mail change") { store.undo() }.keyboardShortcut("z", modifiers: .command).disabled(store.lastUndo == nil) }
            CommandMenu("Message") { action("Reply", "reply", needsSelection: true); action("Reply all", "replyAll", needsSelection: true); Button("Forward") { store.newCompose(kind: "forward") }.disabled(store.selected == nil); Divider(); action("Apply label…", "label", needsSelection: true); action("Archive", "archive", needsSelection: true); action("Move to Trash", "trash", needsSelection: true); action("Clear selection", "clear") }
            CommandMenu("Navigate") { action("Next message", "next"); action("Previous message", "previous"); action("Search mail", "search"); action("Refresh mail", "refresh"); action("Toggle sidebar", "sidebar") }
        }
    }
    private func action(_ title: String, _ name: String, needsSelection: Bool = false) -> some View {
        let shortcut = store.preferences.shortcuts[name] ?? .init(key: "?")
        return Button(title) { store.perform(name) }.keyboardShortcut((["next", "previous"].contains(name) && (store.compose != nil || store.selectedDraftID != nil)) ? nil : KeyboardShortcut(shortcut.equivalent, modifiers: shortcut.modifiers)).disabled(needsSelection && (["reply", "replyAll"].contains(name) ? store.selected == nil : store.actionIDs.isEmpty))
    }
}

extension Shortcut {
    var equivalent: KeyEquivalent {
        switch key { case "up": return .upArrow; case "down": return .downArrow; case "escape": return .escape; case "delete": return .delete; case "return": return .return; default: return KeyEquivalent(key.first ?? "?") }
    }
    var modifiers: EventModifiers { var m: EventModifiers = []; if command { m.insert(.command) }; if shift { m.insert(.shift) }; if option { m.insert(.option) }; return m }
    static func fromEvent(_ event: NSEvent) -> Shortcut? {
        guard !event.modifierFlags.contains(.control) else { return nil }
        let key: String
        switch event.keyCode {
        case 126: key = "up"
        case 125: key = "down"
        case 53: key = "escape"
        case 51: key = "delete"
        case 36: key = "return"
        default: guard let character = event.charactersIgnoringModifiers?.lowercased(), character.count == 1 else { return nil }; key = character
        }
        return .init(key: key, command: event.modifierFlags.contains(.command), shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option))
    }
}

@MainActor
final class PostDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var promptCount = 0
    weak var store: MailStore?
    private var monitor: Any?
    private var flagsMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Let macOS select the catalog's light, dark, and Liquid Glass variants.
        // Assigning a static NSImage here overrides that system appearance handling.
        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateCommandHints(event.modifierFlags.contains(.command))
            return event
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.updateCommandHints(false) } }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self else { return event }; return self.handle(event) }
    }
    func connect(_ store: MailStore) { self.store = store }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let isTest = notification.request.content.userInfo["test"] as? Bool == true
            completionHandler(isTest || (self.store?.preferences.notificationForeground ?? false) ? [.banner, .list, .sound] : [.list])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Post" }?.makeKeyAndOrderFront(nil)
            if let id = response.notification.request.content.userInfo["messageID"] as? String, let store = self.store {
                store.chooseFolder("primary")
                store.select(id)
            }
            completionHandler()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { store?.persist(); store?.flushCache(); if let monitor { NSEvent.removeMonitor(monitor) } }
    private var hintTask: Task<Void, Never>?
    private func updateCommandHints(_ held: Bool) {
        hintTask?.cancel(); store?.commandHeld = false
        guard held else { return }
        hintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.store?.commandHeld = true
        }
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command) { hintTask?.cancel(); store?.commandHeld = false }
        guard Self.promptCount == 0 else { return event }
        guard let store, let shortcut = Shortcut.fromEvent(event) else { return event }
        if let action = store.recordingShortcut {
            if [Shortcut(key: "q", command: true), Shortcut(key: "w", command: true), Shortcut(key: ",", command: true)].contains(shortcut) { store.error = "That shortcut belongs to macOS. Choose another one." }
            else if action.hasPrefix("label:") { _ = store.setLabelShortcut(String(action.dropFirst(6)), value: shortcut) }
            else { _ = store.setShortcut(action, value: shortcut) }
            store.recordingShortcut = nil; return nil
        }
        guard !store.showSettings, !store.showLabels else { return event }
        if shortcut == store.preferences.shortcuts["clear"], store.compose != nil || store.selectedDraftID != nil {
            store.composerDismissRequest += 1; return nil
        }
        guard store.compose == nil else { return event }
        let isEditing = NSApp.keyWindow?.firstResponder is NSTextView || NSApp.keyWindow?.firstResponder is NSTextField
        if shortcut == store.preferences.shortcuts["clear"] { NSApp.keyWindow?.makeFirstResponder(nil); store.perform("clear"); return nil }
        if isEditing || store.selectedDraftID != nil { return event }
        if shortcut.shift, !shortcut.command, !shortcut.option, ["up", "down"].contains(shortcut.key) {
            store.extendNavigation(shortcut.key == "down" ? 1 : -1); return nil
        }
        if store.selectedID == nil, store.selectedDraftID == nil,
           let label = store.shortcutLabels().first(where: { $0.1 == shortcut })?.0 {
            store.chooseFolder(label.id); return nil
        }
        guard let action = store.preferences.shortcuts.first(where: { $0.value == shortcut })?.key else { return event }
        store.perform(action); return nil
    }
}
