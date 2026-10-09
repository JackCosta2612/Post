import Foundation
import AppKit

struct MailAttachment: Codable, Identifiable, Equatable {
    var id: String
    var cachedFile: String? = nil
    var name: String
    var mimeType: String
    var size: Int
    var data: Data?
    var messageID: String? = nil
    var contentID: String? = nil
}

struct MailMessage: Codable, Identifiable, Equatable {
    var id: String
    var threadID: String
    var from: String
    var to: String
    var cc: String = ""
    var bcc: String? = nil
    var replyTo: String = ""
    var subject: String
    var snippet: String
    var body: String
    var html: String = ""
    var date: Date
    var labels: Set<String>
    var attachments: [MailAttachment] = []
    var rfcMessageID: String = ""
    var references: String = ""
    mutating func resolveInlineImages(reusing cached: MailMessage? = nil) {
        for i in attachments.indices {
            if let saved = cached?.attachments.first(where: { $0.id == attachments[i].id && $0.mimeType == attachments[i].mimeType }) {
                if attachments[i].data == nil { attachments[i].data = saved.data }
                if attachments[i].contentID == nil { attachments[i].contentID = saved.contentID }
            }
        }
        guard let regex = try? NSRegularExpression(pattern: "cid:([^\\\"'\\s<>]+)", options: .caseInsensitive) else { return }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard let identifierRange = Range(match.range(at: 1), in: html), let range = Range(match.range, in: html) else { continue }
            let identifier = String(html[identifierRange]).removingPercentEncoding ?? String(html[identifierRange])
            guard let image = attachments.first(where: { Self.normalizedContentID($0.contentID ?? "") == Self.normalizedContentID(identifier) && $0.data?.isEmpty == false }), let bytes = image.data else { continue }
            html.replaceSubrange(range, with: "data:" + image.mimeType + ";base64," + bytes.base64EncodedString())
        }
    }
    static func normalizedContentID(_ value: String) -> String {
        (value.removingPercentEncoding ?? value).trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n")).lowercased()
    }
    var unresolvedImageIDs: Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "cid:([^\\\"'\\s<>]+)", options: .caseInsensitive) else { return [] }
        return Set(regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap {
            Range($0.range(at: 1), in: html).map { Self.normalizedContentID(String(html[$0])) }
        })
    }
    var unread: Bool { labels.contains("UNREAD") }
    var senderName: String { from.split(separator: "<").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") ?? from }
    var recipientNames: String {
        let value = to.isEmpty ? (cc.isEmpty ? bcc ?? "" : cc) : to
        var recipients: [String] = [], current = "", quoted = false, inAddress = false
        for character in value {
            if character == "\"" { quoted.toggle() }
            if !quoted && character == "<" { inAddress = true }
            if !quoted && character == ">" { inAddress = false }
            if character == "," && !quoted && !inAddress { recipients.append(current); current = "" }
            else { current.append(character) }
        }
        recipients.append(current)
        let names = recipients.map { recipient -> String in
            let clean = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = clean.split(separator: "<", omittingEmptySubsequences: false).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
            return name.isEmpty ? Self.address(clean) : name
        }.filter { !$0.isEmpty }
        return names.isEmpty ? "No recipient" : names.joined(separator: ", ")
    }
    var senderAddress: String { Self.address(from) }
    static func address(_ value: String) -> String {
        if let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">") { return String(value[value.index(after: start)..<end]) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MailFolder: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var query: String
    var unreadCount: Int = 0
    var totalCount: Int = 0
    var isCustom: Bool = false
    func contains(_ message: MailMessage) -> Bool {
        switch id {
        case "primary": return message.labels.contains("INBOX") && message.labels.contains("CATEGORY_PERSONAL")
        case "all": return message.labels.isDisjoint(with: ["TRASH", "SPAM", "DRAFT", "SENT"])
        default: return message.labels.contains(id)
        }
    }
    static let defaults: [MailFolder] = [
        .init(id: "primary", name: "Primary", icon: "tray", query: "in:inbox category:primary"),
        .init(id: "confirmations", name: "Application confirmations", icon: "doc.text", query: "label:\"Application confirmations\"", isCustom: true),
        .init(id: "rejections", name: "Rejections", icon: "xmark.circle", query: "label:Rejections", isCustom: true),
        .init(id: "CATEGORY_PROMOTIONS", name: "Promotions", icon: "tag", query: "category:promotions"),
        .init(id: "newsletters", name: "Newsletters", icon: "newspaper", query: "label:Newsletters", isCustom: true),
        .init(id: "all", name: "All mail", icon: "envelope", query: "-in:trash -in:spam -in:drafts -in:sent"),
        .init(id: "STARRED", name: "Starred", icon: "star", query: "is:starred"),
        .init(id: "SENT", name: "Sent", icon: "paperplane", query: "in:sent"),
        .init(id: "DRAFT", name: "Drafts", icon: "square.and.pencil", query: "in:drafts"),
        .init(id: "SPAM", name: "Spam", icon: "exclamationmark.shield", query: "in:spam"),
        .init(id: "TRASH", name: "Trash", icon: "trash", query: "in:trash")
    ]
}

struct Shortcut: Codable, Equatable {
    var key: String
    var command: Bool = false
    var shift: Bool = false
    var option: Bool = false
    var display: String {
        (command ? "⌘" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (["up": "↑", "down": "↓", "escape": "Esc", "delete": "⌫", "return": "↩" ][key] ?? key.uppercased())
    }
    static let defaults: [String: Shortcut] = [
        "reply": .init(key: "r", command: true), "replyAll": .init(key: "r", command: true, shift: true),
        "next": .init(key: "down"), "previous": .init(key: "up"), "label": .init(key: "l"),
        "trash": .init(key: "delete"), "clear": .init(key: "escape"), "archive": .init(key: "e"),
        "compose": .init(key: "n", command: true), "search": .init(key: "f", command: true),
        "refresh": .init(key: "r", command: true, shift: true, option: true), "sidebar": .init(key: "s", command: true)
    ]
    static let names: [(String, String)] = [("reply", "Reply"), ("replyAll", "Reply all"), ("next", "Next message"), ("previous", "Previous message"), ("label", "Apply label"), ("trash", "Move to Trash"), ("clear", "Clear selection"), ("archive", "Archive"), ("compose", "Compose"), ("search", "Search"), ("refresh", "Refresh mail"), ("sidebar", "Toggle sidebar")]
    static func parse(_ value: String) -> Shortcut? {
        let lower = value.lowercased().replacingOccurrences(of: " ", with: "")
        var key = lower.replacingOccurrences(of: "⌘", with: "").replacingOccurrences(of: "⇧", with: "").replacingOccurrences(of: "⌥", with: "")
        for modifier in ["command+", "cmd+", "shift+", "option+", "alt+"] { key = key.replacingOccurrences(of: modifier, with: "") }
        key = ["↑": "up", "↓": "down", "esc": "escape", "⌫": "delete", "backspace": "delete", "↩": "return"][key] ?? key
        guard key.count == 1 || ["up", "down", "escape", "delete", "return"].contains(key) else { return nil }
        return .init(key: key, command: lower.contains("⌘") || lower.contains("cmd+") || lower.contains("command+"), shift: lower.contains("⇧") || lower.contains("shift+"), option: lower.contains("⌥") || lower.contains("option+") || lower.contains("alt+"))
    }
}

struct MailPreferences: Codable {
    var undoSendDelay: Int? = nil
    var readDelay: Int? = nil
    var groupConversations: Bool? = nil
    var boldUnread: Bool? = nil
    var showShortcutHints: Bool? = nil
    var interfaceFont: String? = nil
    var customEmailColors: Bool? = nil
    var readingFont: String? = nil
    var readingSize: Double? = nil
    var listSize: Double? = nil
    var listDensity: String? = nil
    var composerFont: String? = nil
    var composerSize: Double? = nil
    var composerColor: String? = nil
    var composerSpacing: Double? = nil
    var accentColor: String? = nil
    var accentHex: String? = nil
    var cacheMode: String? = nil
    var labelShortcuts: [String: Shortcut]? = nil
    var notificationLabels: Set<String>? = nil
    var notificationSenders: String? = nil
    var quietHours: Bool? = nil
    var quietStart: Int? = nil
    var quietEnd: Int? = nil
    var showNotificationSender: Bool? = nil
    var showNotificationSubject: Bool? = nil
    var showNotificationBody: Bool? = nil
    var sidebarLabelOrder: [String]? = nil
    var sidebarBadges: Bool? = nil
    var hiddenSidebarLabels: Set<String>? = nil
    var collapsed = false
    var totalCounts = false
    var notifications = false
    var remoteImages = false
    var markRead = true
    var shortcuts = Shortcut.defaults
    var signature = ""
    var learnLabels: Bool? = nil
    var automaticLabeling: Bool? = nil
    var automaticLabelTargets: Set<String>? = nil
    var primaryMode: String? = nil
    var primaryIncludedLabels: Set<String>? = nil
    var appearance: String? = nil
    var downloadDirectory: String? = nil
    var notificationScope: String? = nil
    var notificationSound: Bool? = nil
    var notificationSoundName: String? = nil
    var notificationPreview: Bool? = nil
    var notificationForeground: Bool? = nil
}

struct ComposeDraft: Codable, Identifiable {
    var id: String = UUID().uuidString
    var scheduledAt: Date?
    var deliveryState: String?
    var deliveryKind: String?
    var richBody: Data?
    var gmailDraftID: String?
    var to: String = ""
    var cc: String = ""
    var bcc: String = ""
    var subject: String = ""
    var body: String = ""
    var quotedText: String?
    var quotedHTML: String?
    var quoteHeading: String?
    var localChanges: Bool?
    var threadID: String?
    var inReplyTo: String = ""
    var references: String = ""
    var attachments: [MailAttachment] = []
    func hasUserChanges(from baseline: ComposeDraft) -> Bool {
        func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return clean(body) != clean(baseline.body) || clean(to) != clean(baseline.to) || clean(cc) != clean(baseline.cc) || clean(bcc) != clean(baseline.bcc) || clean(subject) != clean(baseline.subject) || (!clean(body).isEmpty && richBody != baseline.richBody) || attachments != baseline.attachments
    }
    mutating func separateLegacyQuote() {
        guard quotedText == nil, let start = body.range(of: "\n\nOn "), let headingEnd = body.range(of: " wrote:\n", range: start.upperBound..<body.endIndex) else { return }
        quoteHeading = String(body[start.lowerBound..<headingEnd.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        quotedText = body[headingEnd.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).map { line in line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line) }.joined(separator: "\n")
        body = String(body[..<start.lowerBound])
    }
    var updated = Date()
}

struct PendingChange: Codable, Identifiable {
    var id = UUID().uuidString
    var messageID: String
    var add: [String]
    var remove: [String]
}

struct FolderSnapshot: Codable {
    var ids: Set<String>
    var nextPage: String?
}

struct MailCache: Codable {
    var messages: [MailMessage] = []
    var folders: [MailFolder] = []
    var drafts: [ComposeDraft] = []
    var pending: [PendingChange] = []
    var lastSync: Date?
    var account: String?
    var historyID: String? = nil
    var preferences = MailPreferences()
    var folderSnapshots: [String: FolderSnapshot]? = nil
    var completedThreads: [String]? = nil
    var labelLearning: LabelLearning? = nil
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s, options: .ignoreUnknownCharacters)
    }
}

enum MailError: LocalizedError {
    case message(String)
    case http(Int, String)
    case rateLimited
    var errorDescription: String? {
        switch self { case .message(let text), .http(_, let text): return text
        case .rateLimited: return "Gmail asked Post to slow down. Sync will resume automatically; cached mail remains available." }
    }
}

enum MIMEBuilder {
    static func clean(_ value: String) -> String { value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "") }
    static func encoded(_ value: String) -> String { "=?UTF-8?B?\(Data(clean(value).utf8).base64EncodedString())?=" }
    static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func inlineImages(_ html: String) -> (html: String, parts: [MailAttachment]) {
        guard let regex = try? NSRegularExpression(pattern: #"data:(image/[a-zA-Z0-9.+-]+);base64,([a-zA-Z0-9+/=\r\n]+)"#, options: .caseInsensitive) else { return (html, []) }
        var output = html, parts: [MailAttachment] = []
        var identifiers: [String: String] = [:]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: output), let typeRange = Range(match.range(at: 1), in: html), let dataRange = Range(match.range(at: 2), in: html),
                  let data = Data(base64Encoded: String(html[dataRange]), options: .ignoreUnknownCharacters), !data.isEmpty else { continue }
            let source = String(html[Range(match.range, in: html)!])
            let identifier: String
            if let existing = identifiers[source] { identifier = existing }
            else {
                identifier = "image-\(UUID().uuidString)@post.local"
                identifiers[source] = identifier
                parts.append(.init(id: identifier, name: "", mimeType: String(html[typeRange]), size: data.count, data: data, contentID: identifier))
            }
            output.replaceSubrange(range, with: "cid:" + identifier)
        }
        return (output, parts)
    }
    static func build(_ draft: ComposeDraft, from: String) throws -> Data {
        guard !draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MailError.message("Add a recipient before sending.") }
        let boundary = "post-\(UUID().uuidString)"
        var h = ["From: \(clean(from))", "To: \(clean(draft.to))", "Subject: \(encoded(draft.subject))", "MIME-Version: 1.0", "Message-ID: <\(UUID().uuidString)@post.local>"]
        if !draft.cc.isEmpty { h.append("Cc: \(clean(draft.cc))") }
        if !draft.bcc.isEmpty { h.append("Bcc: \(clean(draft.bcc))") }
        if !draft.inReplyTo.isEmpty { h += ["In-Reply-To: \(clean(draft.inReplyTo))", "References: \(clean(draft.references + " " + draft.inReplyTo))"] }
        h.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        let plain = draft.body + (draft.quotedText.map { "\n\n" + (draft.quoteHeading ?? "Previous message") + "\n" + $0 } ?? "")
        let base64: (String) -> String = { Data($0.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) }
        var s = h.joined(separator: "\r\n") + "\r\n\r\n--\(boundary)\r\n"
        if draft.quotedText != nil || draft.richBody != nil {
            let quote = draft.quotedText ?? ""
            let alternative = "alternative-\(UUID().uuidString)"
            let original = draft.quotedHTML ?? "<div style='white-space:pre-wrap'>\(htmlEscape(quote))</div>"
            let formatted = draft.richBody.flatMap { try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) }
            let richHTML = formatted.flatMap { try? $0.data(from: NSRange(location: 0, length: $0.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) }.flatMap { String(data: $0, encoding: .utf8) }
            let content = richHTML.flatMap { value -> String? in
                guard let start = value.range(of: "<body"), let open = value.range(of: ">", range: start.lowerBound..<value.endIndex), let end = value.range(of: "</body>") else { return nil }
                // Apple's HTML exporter uses CSS classes. Preserve its style block with the body.
                let styles = value.range(of: "<style", options: .caseInsensitive).flatMap { a in value.range(of: "</style>", options: .caseInsensitive).map { String(value[a.lowerBound..<$0.upperBound]) } } ?? ""
                return styles + String(value[open.upperBound..<end.lowerBound])
            } ?? "<div style='white-space:pre-wrap'>\(htmlEscape(draft.body))</div>"
            let html = content + (draft.quotedText == nil ? "" : "<br><div>\(htmlEscape(draft.quoteHeading ?? "Previous message"))</div><blockquote style='border-left:2px solid #bccbd9;padding-left:16px;margin-left:0'>\(original)</blockquote>")
            let embedded = inlineImages(html)
            let related = "related-\(UUID().uuidString)"
            s += "Content-Type: multipart/alternative; boundary=\"\(alternative)\"\r\n\r\n--\(alternative)\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(base64(plain))\r\n--\(alternative)\r\n"
            if !embedded.parts.isEmpty {
                s += "Content-Type: multipart/related; boundary=\"\(related)\"; type=\"text/html\"\r\n\r\n--\(related)\r\n"
            }
            s += "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(base64(embedded.html))"
            for image in embedded.parts {
                s += "\r\n--\(related)\r\nContent-Type: \(image.mimeType)\r\nContent-ID: <\(image.contentID!)>\r\nContent-Disposition: inline\r\nContent-Transfer-Encoding: base64\r\n\r\n" + image.data!.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
            }
            if !embedded.parts.isEmpty { s += "\r\n--\(related)--" }
            s += "\r\n--\(alternative)--"

        } else {
            s += "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + base64(plain)
        }
        for attachment in draft.attachments {
            // Quoted inline media is already included in the related HTML part.
            if attachment.contentID != nil, let bytes = attachment.data,
               draft.quotedHTML?.contains("data:" + attachment.mimeType + ";base64," + bytes.base64EncodedString()) == true { continue }
            guard let data = attachment.data else { throw MailError.message("The attachment \(attachment.name) is unavailable. Attach it again.") }
            let name = clean(attachment.name).replacingOccurrences(of: "\"", with: "'")
            s += "\r\n--\(boundary)\r\nContent-Type: \(clean(attachment.mimeType))\r\nContent-Disposition: attachment; filename=\"\(name)\"\r\nContent-Transfer-Encoding: base64\r\n\r\n" + data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        }
        s += "\r\n--\(boundary)--\r\n"
        guard s.utf8.count < 34_000_000 else { throw MailError.message("This message is too large. Use smaller attachments.") }
        return Data(s.utf8)
    }
}

/// Keep quoted history available without repeating it in every conversation message.
enum MessageQuote {
    static func split(_ text: String) -> (body: String, quote: String?) {
        let lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value.hasPrefix(">") || (value.hasPrefix("On ") && value.hasSuffix("wrote:")) || value == "-----Original Message-----"
        }) else { return (text, nil) }
        return (lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), lines[index...].joined(separator: "\n"))
    }
}

// Repair cached MIME body parts produced by older versions, without a network request.
extension MailMessage {
    mutating func recoverBodyParts() {
        let parts = attachments.filter { $0.name == "Inline image" && ["text/html", "text/plain"].contains($0.mimeType) && $0.data != nil }
        for part in parts {
            guard let data = part.data, let text = String(data: data, encoding: .utf8) else { continue }
            if part.mimeType == "text/html", html.isEmpty { html = text }
            if part.mimeType == "text/plain" { body = text }
        }
        attachments.removeAll { part in parts.contains { $0.id == part.id } }
    }
}

enum MessageHTML {
    static func cachedImageURLs(_ html: String) -> String {
        // Rewrite image sources and CSS backgrounds, leaving links unchanged.
        let pattern = #"(?i)(\bsrc\s*=\s*["']|url\(\s*["']?)(https?://[^"'<>\s)]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range(at: 2), in: result) else { continue }
            let value = String(result[range])
            result.replaceSubrange(range, with: value.replacingOccurrences(of: "://", with: "/", range: value.range(of: "://")).withImageScheme)
        }
        return result
    }
    static func originalImageURL(_ url: URL) -> URL? {
        guard url.scheme == "post-image", let host = url.host, ["https", "http"].contains(host) else { return nil }
        let value = url.absoluteString.replacingOccurrences(of: "post-image://" + host + "/", with: host + "://")
        return URL(string: value.replacingOccurrences(of: "&amp;", with: "&"))
    }
}
private extension String { var withImageScheme: String { "post-image://" + self } }

struct MailDrag: Codable { var ids: [String]; var source: String }

// macOS keeps the original filenames for its renamed alert sounds.
enum NewMailSound {
    static let choices: [(name: String, file: String)] = [
        ("Submerge", "Submarine"), ("Breeze", "Blow"), ("Bubble", "Pop"),
        ("Crystal", "Glass"), ("Funky", "Funk"), ("Hero", "Hero"),
        ("Jump", "Frog"), ("Mezzo", "Basso"), ("Pebble", "Bottle"),
        ("Pluck", "Purr"), ("Pong", "Ping"), ("Sonumi", "Sosumi"),
        ("Sonar", "Morse"), ("Tink", "Tink")
    ]
    static func filename(for choice: String?) -> String? {
        if choice == "default" { return nil }
        let file = choices.first { $0.file == (choice ?? "Submarine") }?.file ?? "Submarine"
        return file + ".aiff"
    }
}

// A bounded, on-device classifier trained only from explicit label choices.
struct LabelExample: Codable, Identifiable {
    var id: String
    var target: String
    var sender: String
    var terms: [String: Double]
    var updated: Date
}
struct AutomaticLabelMove: Codable, Identifiable {
    var id = UUID().uuidString
    var messageID: String
    var target: String
    var subject: String
    var previousLabels: Set<String>
    var date = Date()
}
struct LabelLearning: Codable {
    static let primary = "__primary__"
    var examples: [LabelExample] = []
    var recentMoves: [AutomaticLabelMove] = []
    static func terms(_ message: MailMessage) -> [String: Double] {
        let ignored = Set("the and for you your this that with from have has was are will our not but can please thanks thank regards best dear hello hi kind team email message unsubscribe click http https www com re fwd on to of a in it is be at as we i an or by il la le lo di da del della che per con una un e è si non grazie saluti buongiorno cordiali".split(separator: " ").map(String.init))
        func words(_ text: String) -> [String] {
            let clean = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return clean.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 3 && $0.count <= 30 && !ignored.contains($0) }
        }
        var result: [String: Double] = [:]
        for word in Set(words(message.subject)) { result[word] = 4 }
        // Ignore repeated quoted history and signatures; cap the amount of text processed.
        let text = MessageQuote.split(message.body).body.components(separatedBy: "\n--").first ?? message.body
        for word in Set(words(String(text.prefix(6000))).prefix(180)) { result[word] = max(result[word] ?? 0, 1) }
        return result
    }
    mutating func learn(_ message: MailMessage, target: String) {
        let features = Self.terms(message)
        guard features.count >= 3 else { return }
        examples.removeAll { $0.id == message.id }
        examples.append(.init(id: message.id, target: target, sender: message.senderAddress.lowercased(), terms: features, updated: Date()))
        if examples.count > 1000 { examples.removeFirst(examples.count - 1000) }
    }
    func prediction(_ message: MailMessage, allowed: Set<String>) -> String? {
        let query = Self.terms(message)
        guard query.count >= 3 else { return nil }
        let usable = examples.filter { allowed.contains($0.target) || $0.target == Self.primary }
        guard !usable.isEmpty else { return nil }
        // Repeated, unanimous corrections establish an exact-sender preference.
        // Changing newsletter topics must not erase that evidence. Any conflicting
        // destination, including Primary, keeps this sender on content matching.
        let sender = message.senderAddress.lowercased()
        let senderHistory = examples.filter { $0.id != message.id && $0.sender == sender }
        if !sender.isEmpty, Set(senderHistory.map(\.id)).count >= 3,
           let target = senderHistory.first?.target, target != Self.primary,
           allowed.contains(target), senderHistory.allSatisfy({ $0.target == target }) {
            return target
        }
        let groups = Dictionary(grouping: usable, by: \.target)
        // Terms repeated across different labels carry less evidence than distinctive content.
        let prevalence = groups.values.reduce(into: [String: Int]()) { counts, values in
            for word in Set(values.flatMap { $0.terms.keys }) { counts[word, default: 0] += 1 }
        }
        func score(_ example: LabelExample) -> Double {
            func weight(_ word: String, _ amount: Double) -> Double { amount / Double(prevalence[word] ?? 1) }
            let shared = query.reduce(0.0) { sum, pair in sum + weight(pair.key, min(pair.value, example.terms[pair.key] ?? 0)) }
            let total = query.reduce(0.0) { $0 + weight($1.key, $1.value) } + example.terms.reduce(0.0) { $0 + weight($1.key, $1.value) }
            // Sender agreement supports content evidence, but never substitutes for it.
            let content = total > 0 ? 2 * shared / total : 0
            return min(1, content + (content >= 0.55 && example.sender == message.senderAddress.lowercased() ? 0.05 : 0))
        }
        var ranked: [(String, Double, Int, Bool)] = []
        for (target, values) in groups {
            let otherExamples = values.filter { $0.id != message.id }
            let senderScores = otherExamples.filter { $0.sender == message.senderAddress.lowercased() }.map(score).sorted(by: >)
            // Two distinct, closely matching corrections from this sender are enough.
            // Content still has to agree; sender-only rules would mix interviews and rejections.
            let repeatedSender = senderScores.count >= 2 && senderScores[1] >= 0.75
            let scores = otherExamples.map(score).sorted(by: >)
            let neighbors = Array((repeatedSender ? senderScores : scores).prefix(repeatedSender ? 2 : 3))
            let sum: Double = neighbors.reduce(0.0) { $0 + $1 }
            let mean: Double = neighbors.isEmpty ? 0.0 : sum / Double(neighbors.count)
            let strong = neighbors.filter { $0 >= 0.65 }.count
            ranked.append((target, mean, strong, repeatedSender))
        }
        ranked.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        guard let best = ranked.first, best.0 != Self.primary, (best.2 >= 3 || best.3), best.1 >= 0.72,
              best.1 - (ranked.dropFirst().first?.1 ?? 0) >= 0.15 else { return nil }
        return best.0
    }
}
