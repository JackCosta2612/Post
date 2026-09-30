import SwiftUI
import AppKit

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
final class PostDelegate: NSObject, NSApplicationDelegate {
    static var promptCount = 0
    weak var store: MailStore?
    private var monitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "Post", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self else { return event }; return self.handle(event) }
    }
    func connect(_ store: MailStore) { self.store = store }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { store?.persist(); store?.flushCache(); if let monitor { NSEvent.removeMonitor(monitor) } }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard Self.promptCount == 0 else { return event }
        guard let store, let shortcut = Shortcut.fromEvent(event) else { return event }
        if let action = store.recordingShortcut {
            if [Shortcut(key: "q", command: true), Shortcut(key: "w", command: true), Shortcut(key: ",", command: true)].contains(shortcut) { store.error = "That shortcut belongs to macOS. Choose another one." }
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
        if isEditing { return event }
        if shortcut.shift, !shortcut.command, !shortcut.option, ["up", "down"].contains(shortcut.key) {
            store.extendNavigation(shortcut.key == "down" ? 1 : -1); return nil
        }
        guard let action = store.preferences.shortcuts.first(where: { $0.value == shortcut })?.key else { return event }
        store.perform(action); return nil
    }
}
