import SwiftUI
import AppKit

/// Native drag threshold avoids starting a drag on small, high-DPI mouse movements.
struct MailDragSurface: NSViewRepresentable {
    var payload: String?
    var title: String
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.payload = payload; view.title = title }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.removeMonitor() }
    final class Surface: NSView, NSDraggingSource {
        var payload: String?
        var title = ""
        private var origin: NSPoint?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, event.window === self.window, self.payload != nil else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if event.type == .leftMouseDown { self.origin = self.bounds.contains(point) ? point : nil }
                if event.type == .leftMouseUp { self.origin = nil }
                guard event.type == .leftMouseDragged, let origin = self.origin,
                      hypot(point.x - origin.x, point.y - origin.y) >= 10, let payload = self.payload else { return event }
                self.origin = nil
                LabelDragState.shared.payload = payload
                let item = NSPasteboardItem(); item.setString(payload, forType: .string)
                let drag = NSDraggingItem(pasteboardWriter: item)
                let image = NSImage(size: NSSize(width: 240, height: 38), flipped: false) { rect in
                    NSColor.windowBackgroundColor.withAlphaComponent(0.42).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                    let text = NSString(string: String(self.title.prefix(36)))
                    text.draw(in: NSRect(x: 12, y: 10, width: 216, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.48)])
                    return true
                }
                drag.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 19, width: 240, height: 38), contents: image)
                let session = self.beginDraggingSession(with: [drag], event: event, source: self)
                session.animatesToStartingPositionsOnCancelOrFail = false
                return nil
            }
        }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; origin = nil }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { LabelDragState.shared.payload = nil; LabelDragState.shared.target = nil }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    }
}

struct SubjectInput: NSViewRepresentable {
    @Binding var text: String
    var onTab: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(); field.isBordered = false; field.drawsBackground = false
        field.font = NSFont(name: PostPalette.shared.interfaceFont, size: 13) ?? .systemFont(ofSize: 13); field.delegate = context.coordinator
        field.setAccessibilityLabel("Subject"); return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.font = NSFont(name: PostPalette.shared.interfaceFont, size: 13) ?? .systemFont(ofSize: 13); context.coordinator.parent = self; if field.stringValue != text { field.stringValue = text } }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SubjectInput
        init(_ parent: SubjectInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) { if let field = notification.object as? NSTextField { parent.text = field.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) { parent.onTab(); return true }
            return false
        }
    }
}

struct RichComposer: NSViewRepresentable {
    @Binding var text: String
    @Binding var richData: Data?
    var fontName: String
    var size: Double
    var color: NSColor
    var spacing: Double
    @Binding var editor: NSTextView?
    var focusOnLoad = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let view = ComposerTextView(); view.focusOnLoad = focusOnLoad; view.isRichText = true; view.allowsUndo = true; view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 8); view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.setAccessibilityLabel("Message")
        if let richData, let attributed = try? NSAttributedString(data: richData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) { view.textStorage?.setAttributedString(attributed)
            if color == NSColor.textColor {
                view.textStorage?.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                    if let saved = value as? NSColor, saved.usingColorSpace(.deviceRGB).map({ $0.redComponent < 0.01 && $0.greenComponent < 0.01 && $0.blueComponent < 0.01 }) == true { view.textStorage?.addAttribute(.foregroundColor, value: NSColor.textColor, range: range) }
                }
            }
        }
        else { view.string = text }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing
        view.typingAttributes = [.font: NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: size) ?? NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph]
        if richData == nil { view.textStorage?.addAttributes(view.typingAttributes, range: NSRange(location: 0, length: view.string.utf16.count)) }
        scroll.documentView = view
        DispatchQueue.main.async { editor = view }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
        let style = fontName + String(size) + color.description + String(spacing)
        if context.coordinator.style != style {
            if !context.coordinator.style.isEmpty {
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: size) ?? NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: paragraph]
                let range = view.selectedRange().length > 0 ? view.selectedRange() : NSRange(location: 0, length: view.string.utf16.count)
                view.textStorage?.addAttributes(attributes, range: range); view.typingAttributes = attributes
                context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
            }
            context.coordinator.style = style
        }
    }
    final class ComposerTextView: NSTextView {
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.intersection([.command, .option, .control]) == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "b": postToggleTrait(.boldFontMask); return
                case "i": postToggleTrait(.italicFontMask); return
                case "u": postToggleUnderline(); return
                default: break
                }
            }
            super.keyDown(with: event)
        }
        var focusOnLoad = false
        private var focusedOnce = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard focusOnLoad, !focusedOnce, window != nil else { return }
            focusedOnce = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.window?.makeFirstResponder(self)
                self.setSelectedRange(NSRange(location: 0, length: 0)); self.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichComposer
        var style = ""
        init(_ parent: RichComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            let outgoing = NSMutableAttributedString(attributedString: view.attributedString())
            outgoing.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: outgoing.length)) { value, range, _ in
                if let color = value as? NSColor, color == NSColor.textColor { outgoing.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
            }
            parent.richData = try? outgoing.data(from: NSRange(location: 0, length: view.string.utf16.count), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }
    }
}

extension NSColor {
    convenience init?(postHex: String) {
        guard postHex.count == 6, let value = UInt32(postHex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var postHex: String {
        let rgb = usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }
}

final class LabelDragState: ObservableObject {
    static let shared = LabelDragState()
    @Published var payload: String?
    @Published var target: String?
    @Published var after = false
}
struct LabelDropTarget: ViewModifier {
    let id: String
    let height: CGFloat
    let store: MailStore
    let acceptsMessages: Bool
    @ObservedObject private var drag = LabelDragState.shared
    func body(content: Content) -> some View {
        content.background {
            if drag.target == id && drag.payload?.hasPrefix("post-mail:") == true {
                RoundedRectangle(cornerRadius: 8).fill(PostStyle.selection).overlay(RoundedRectangle(cornerRadius: 8).stroke(PostStyle.accent.opacity(0.65), lineWidth: 1.5))
            }
        }.animation(.easeOut(duration: 0.12), value: drag.target == id).overlay(alignment: drag.after ? .bottom : .top) {
            if drag.target == id && drag.payload?.hasPrefix("post-label:") == true {
                RoundedRectangle(cornerRadius: 1).fill(PostStyle.accent).frame(height: 2).padding(.horizontal, 4).allowsHitTesting(false)
            }
        }.onDrop(of: [.text], delegate: SidebarDropDelegate(id: id, height: height, store: store, acceptsMessages: acceptsMessages))
    }
}
struct SidebarDropDelegate: DropDelegate {
    let id: String
    let height: CGFloat
    let store: MailStore
    let acceptsMessages: Bool
    func validateDrop(info: DropInfo) -> Bool {
        let payload = LabelDragState.shared.payload ?? ""
        return payload.hasPrefix("post-label:") ? id != "primary" && store.orderedSidebarLabels.contains(where: { $0.id == id }) : acceptsMessages && payload.hasPrefix("post-mail:")
    }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { update(info); return DropProposal(operation: .move) }
    private func update(_ info: DropInfo) { LabelDragState.shared.target = id; LabelDragState.shared.after = info.location.y > height / 2 }
    func dropExited(info: DropInfo) { if LabelDragState.shared.target == id { LabelDragState.shared.target = nil } }
    func performDrop(info: DropInfo) -> Bool {
        guard let payload = LabelDragState.shared.payload else { return false }
        let after = info.location.y > height / 2
        LabelDragState.shared.target = nil
        if payload.hasPrefix("post-label:") { return store.reorderSidebarLabel(String(payload.dropFirst(11)), before: id, after: after) }
        return acceptsMessages && store.handleSidebarDrop([payload], target: id)
    }
}

extension NSTextView {
    func postToggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let range = selectedRange(), manager = NSFontManager.shared
        let fallback = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
        let selectedFont = range.length > 0 ? storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? fallback : fallback
        let oblique = range.length > 0 ? storage.attribute(.obliqueness, at: range.location, effectiveRange: nil) as? Double ?? 0 : typingAttributes[.obliqueness] as? Double ?? 0
        let remove = trait == .italicFontMask ? abs(selectedFont.italicAngle) > 0.01 || oblique != 0 : manager.traits(of: selectedFont).contains(trait)
        func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
            let converted = remove ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            var result: [NSAttributedString.Key: Any] = [.font: converted]
            if trait == .italicFontMask { result[.obliqueness] = !remove && abs(converted.italicAngle) < 0.01 ? 0.2 : 0.0 }
            return result
        }
        if range.length == 0 { typingAttributes.merge(attributes(fallback)) { _, new in new } }
        else {
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in runs.append((subrange, value as? NSFont ?? fallback)) }
            guard shouldChangeText(in: range, replacementString: nil) else { return }
            for (subrange, font) in runs { storage.addAttributes(attributes(font), range: subrange) }
            didChangeText()
        }
        window?.makeFirstResponder(self)
    }
    func postToggleUnderline() {
        let range = selectedRange()
        let current = range.length > 0 ? textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0 : typingAttributes[.underlineStyle] as? Int ?? 0
        let value = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        if range.length == 0 { typingAttributes[.underlineStyle] = value }
        else {
            guard shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage?.addAttribute(.underlineStyle, value: value, range: range); didChangeText()
        }
        window?.makeFirstResponder(self)
    }
}
