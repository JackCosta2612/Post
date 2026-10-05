import Foundation
import AppKit
import Security
import CryptoKit
import Network

enum SecureStore {
    static let service = "com.jack.Post"
    static func read(_ account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
    static func save(_ data: Data, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var a = q; a[kSecValueData as String] = data; a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(a as CFDictionary, nil) == errSecSuccess else { throw MailError.message("Post could not save sign-in securely in Keychain.") }; return
        }
        guard status == errSecSuccess else { throw MailError.message("Post could not update sign-in in Keychain.") }
    }
    static func remove(_ account: String) { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary) }
}

struct OAuthClient: Codable {
    var clientID: String
    var clientSecret: String
}
struct OAuthToken: Codable {
    var access: String
    var refresh: String
    var expiry: Date
    var email: String? = nil
}

final class LoopbackLogin: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Post.OAuth")
    private var listener: NWListener?
    private var callback: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var readyResumed = false
    private let state: String
    init(state: String) { self.state = state }
    func start() async throws -> UInt16 {
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: p)
        listener = l
        return try await withCheckedThrowingContinuation { continuation in
            l.stateUpdateHandler = { state in
                guard !self.readyResumed else { return }
                switch state {
                case .ready: self.readyResumed = true; continuation.resume(returning: l.port!.rawValue)
                case .failed(let error): self.readyResumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    guard let self, let data, let request = String(data: data, encoding: .utf8), let path = request.split(separator: " ").dropFirst().first,
                          let c = URLComponents(string: "http://127.0.0.1\(path)") else { connection.cancel(); return }
                    let params = Dictionary(c.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { a, _ in a })
                    guard c.path == "/oauth/callback", params["state"] == self.state else {
                        let response = Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nInvalid login callback.".utf8)
                        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }); return
                    }
                    let ok = params["code"] != nil
                    let body = ok ? "<h2>Sign-in received</h2><p>You can return to Post.</p>" : "<h2>Sign-in canceled</h2><p>Return to Post to try again.</p>"
                    let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                    self.finish(params["code"].map { .success($0) } ?? .failure(MailError.message("Google sign-in was canceled.")))
                }
            }
            l.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 180) { [weak self] in self?.finish(.failure(MailError.message("Sign-in timed out. Try again."))) }
        }
    }
    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in queue.async { if let result = self.result { continuation.resume(with: result) } else { self.callback = continuation } } }
    }
    private func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result; callback?.resume(with: result); callback = nil; listener?.cancel()
    }
}

actor GmailClient {
    static let sampleAccount = "alex@example.com"
    var client: OAuthClient?
    var token: OAuthToken?
    let session: URLSession
    private let persistCredentials: Bool
    private var requestCosts: [(Date, Int)] = []
    private var cooldownUntil = Date.distantPast
    private var cooldownSeconds: Double = 60
    private var countGeneration = UUID()
    private var countCache: [String: (Date, Int)] = [:]
    private var threadRequests: [String: Task<[MailMessage], Error>] = [:]
    private var attachmentRequests: [String: Task<Data, Error>] = [:]
    private var folderCache: (Date, [MailFolder])?
    static func quotaCost(_ path: String, method: String) -> Int {
        if path.contains("/attachments/") { return 20 }
        if path.hasSuffix("/send") { return 100 }
        if path.hasPrefix("threads/") { return 40 }
        if path == "history" { return 2 }
        if path == "labels" || path.hasPrefix("labels/") { return method == "GET" ? 1 : 5 }
        if path == "profile" { return 1 }
        if path == "messages" || path == "drafts" { return method == "GET" ? 5 : 10 }
        if path.hasSuffix("/modify") || path.hasSuffix("/trash") || path.hasSuffix("/untrash") { return 5 }
        return 20
    }
    private func reserveQuota(_ cost: Int) async throws {
        while true {
            try Task.checkCancellation()
            guard Date() >= cooldownUntil else { throw MailError.rateLimited }
            requestCosts.removeAll { Date().timeIntervalSince($0.0) >= 60 }
            if requestCosts.reduce(0, { $0 + $1.1 }) + cost <= 3000 {
                requestCosts.append((Date(), cost)); return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    init(session: URLSession = .shared, client: OAuthClient? = nil, token: OAuthToken? = nil, restore: Bool = true) {
        self.session = session; self.client = client; self.token = token; self.persistCredentials = restore
        if restore {
            if let data = SecureStore.read("oauth-client") { self.client = try? JSONDecoder().decode(OAuthClient.self, from: data) }
            if let data = SecureStore.read("oauth-token") { self.token = try? JSONDecoder().decode(OAuthToken.self, from: data) }
        }
    }
    func connectionState() -> (Bool, Bool) { (client != nil, client != nil && token != nil) }
    func importClient(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let installed = json["installed"] as? [String: Any], let id = installed["client_id"] as? String, id.hasSuffix(".apps.googleusercontent.com") else { throw MailError.message("Choose the JSON file for a Google Desktop app OAuth client.") }
        let value = OAuthClient(clientID: id, clientSecret: installed["client_secret"] as? String ?? "")
        try SecureStore.save(JSONEncoder().encode(value), account: "oauth-client"); client = value
    }
    func signIn() async throws -> String {
        guard let client else { throw MailError.message("Import your Google Desktop OAuth client first.") }
        let state = UUID().uuidString
        let verifier = Data((0..<64).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let loopback = LoopbackLogin(state: state)
        let port = try await loopback.start()
        let redirect = "http://127.0.0.1:\(port)/oauth/callback"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = ["client_id": client.clientID, "redirect_uri": redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/gmail.modify", "access_type": "offline", "prompt": "consent", "state": state, "code_challenge": challenge, "code_challenge_method": "S256"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let authorizationURL = c.url!
        await MainActor.run { _ = NSWorkspace.shared.open(authorizationURL) }
        let code = try await loopback.waitForCode()
        let response = try await tokenRequest(["code": code, "client_id": client.clientID, "client_secret": client.clientSecret, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier])
        guard let access = response["access_token"] as? String, let refresh = response["refresh_token"] as? String else { throw MailError.message("Google did not grant offline access. Sign in again.") }
        var candidate = OAuthToken(access: access, refresh: refresh, expiry: Date().addingTimeInterval(response["expires_in"] as? Double ?? 3600))
        let previous = token; token = candidate
        do {
            let profile = try await request("profile")
            guard let email = profile["emailAddress"] as? String, !email.isEmpty else { throw MailError.message("Google did not return your Gmail address.") }
            candidate.email = email; token = candidate
            try SecureStore.save(JSONEncoder().encode(candidate), account: "oauth-token")
            return email
        } catch { token = previous; throw error }
    }
    func accountAddress() async throws -> String {
        if let email = token?.email, !email.isEmpty { return email }
        guard let email = try await request("profile")["emailAddress"] as? String else { throw MailError.message("Google did not return your Gmail address.") }
        token?.email = email
        if persistCredentials, let token { try SecureStore.save(JSONEncoder().encode(token), account: "oauth-token") }
        return email
    }
    func disconnect() { token = nil; SecureStore.remove("oauth-token") }
    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var c = URLComponents(); c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.httpBody = c.percentEncodedQuery?.data(using: .utf8)
        return try await execute(r)
    }
    private func accessToken() async throws -> String {
        guard var token, let client else { throw MailError.message("Connect Gmail in Settings to use live mail.") }
        if token.expiry.timeIntervalSinceNow < 90 {
            let response = try await tokenRequest(["client_id": client.clientID, "client_secret": client.clientSecret, "refresh_token": token.refresh, "grant_type": "refresh_token"])
            guard let access = response["access_token"] as? String else { throw MailError.message("Sign in to Google again in Settings.") }
            token.access = access; token.expiry = Date().addingTimeInterval(response["expires_in"] as? Double ?? 3600)
            self.token = token; if persistCredentials { try SecureStore.save(JSONEncoder().encode(token), account: "oauth-token") }
        }
        return token.access
    }
    func request(_ path: String, method: String = "GET", query: [String: String] = [:], labelIDs: [String] = [], body: [String: Any]? = nil) async throws -> [String: Any] {
        try await reserveQuota(Self.quotaCost(path, method: method))
        let access = try await accessToken()
        var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(path)")!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } + labelIDs.map { URLQueryItem(name: "labelIds", value: $0) }
        var r = URLRequest(url: c.url!); r.httpMethod = method; r.timeoutInterval = 30
        r.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await execute(r)
    }
    private func execute(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MailError.message("No response from Google.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let error = json["error"] as? [String: Any]
            let description = error?["message"] as? String ?? json["error_description"] as? String ?? "Google returned error \(http.statusCode)."
            let reasons = (error?["errors"] as? [[String: Any]] ?? []).compactMap { $0["reason"] as? String }
            if request.url?.host == "gmail.googleapis.com", http.statusCode == 429 || (http.statusCode == 403 && (reasons.contains("rateLimitExceeded") || reasons.contains("userRateLimitExceeded") || description.lowercased().contains("quota exceeded"))) {
                let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? cooldownSeconds
                cooldownUntil = Date().addingTimeInterval(max(60, retry))
                cooldownSeconds = min(cooldownSeconds * 2, 300)
                throw MailError.rateLimited
            }
            throw MailError.http(http.statusCode, description)
        }
        return json
    }
    func folders() async throws -> [MailFolder] {
        if let cached = folderCache, Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        let generation = countGeneration
        let response = try await request("labels")
        let labels = response["labels"] as? [[String: Any]] ?? []
        var result = MailFolder.defaults.filter { !$0.isCustom }
        for label in labels where label["type"] as? String == "user" {
            guard let id = label["id"] as? String, let name = label["name"] as? String else { continue }
            let icon = name.lowercased().contains("reject") ? "xmark.circle" : name.lowercased().contains("confirm") ? "doc.text" : name.lowercased().contains("newsletter") ? "newspaper" : "tag"
            let displayName = ["rejection": "Rejections", "application confirmation": "Application confirmations", "newsletters": "Newsletters"][name.lowercased()] ?? name
            result.insert(.init(id: id, name: displayName, icon: icon, query: "label:\"\(name.replacingOccurrences(of: "\"", with: ""))\"", isCustom: true), at: min(result.count, 1))
        }
        for i in result.indices where result[i].id != "primary" && result[i].id != "all" {
            let id = result[i].id
            if result[i].isCustom || id == "CATEGORY_PROMOTIONS" || id == "STARRED" || id == "SENT" {
                // Label metadata includes messages that retain their labels in Trash
                // or Spam. Count the same visible set used by the message list.
                let query = result[i].query + " -in:trash -in:spam"
                result[i].unreadCount = try await count(query: query + " is:unread")
                result[i].totalCount = try await count(query: query)
            } else {
                let detail = try await request("labels/\(id)")
                result[i].unreadCount = detail["messagesUnread"] as? Int ?? 0
                result[i].totalCount = detail["messagesTotal"] as? Int ?? 0
            }
        }
        func rank(_ f: MailFolder) -> Int { if f.id == "primary" { return 0 }; if f.name == "Application confirmations" { return 1 }; if f.name == "Rejections" { return 2 }; if f.id == "CATEGORY_PROMOTIONS" { return 3 }; if f.name == "Newsletters" { return 4 }; if f.isCustom { return 5 }; return 6 + (MailFolder.defaults.firstIndex { $0.id == f.id } ?? 0) }
        let sorted = result.sorted { rank($0) == rank($1) ? $0.name < $1.name : rank($0) < rank($1) }
        if countGeneration == generation { folderCache = (Date(), sorted) }; return sorted
    }
    func list(query: String, page: String? = nil, cached: [MailMessage] = []) async throws -> ([MailMessage], String?) {
        var parameters = ["q": query, "maxResults": "50", "includeSpamTrash": "true"]
        if let page { parameters["pageToken"] = page }
        let json = try await request("messages", query: parameters, labelIDs: Self.requiredLabels(query))
        let cachedMap = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let ids = (json["messages"] as? [[String: String]] ?? []).compactMap { $0["id"] }
        var messages: [MailMessage] = []
        for batchStart in stride(from: 0, to: ids.count, by: 5) {
            let batch = Array(ids[batchStart..<min(ids.count, batchStart + 5)])
            let items = try await withThrowingTaskGroup(of: MailMessage.self) { group in
                for id in batch { group.addTask {
                    if var existing = cachedMap[id] {
                        if !Set(Self.requiredLabels(query)).isSubset(of: existing.labels) {
                            let metadata = try await self.request("messages/\(id)", query: ["format": "minimal"])
                            existing.labels = Set(metadata["labelIds"] as? [String] ?? [])
                        }
                        return existing
                    }
                    return try await self.message(id)
                } }
                var items: [MailMessage] = []; for try await item in group { items.append(item) }; return items
            }
            messages += items
        }
        return (messages.sorted { $0.date > $1.date }, json["nextPageToken"] as? String)
    }
    static func requiredLabels(_ query: String) -> [String] {
        let operators = query.replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression).split(separator: " ")
        var labels: [String] = []
        if operators.contains("in:inbox") { labels.append("INBOX") }
        if operators.contains("is:unread") { labels.append("UNREAD") }
        return labels
    }
    func count(query: String) async throws -> Int {
        if let cached = countCache[query], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        let generation = countGeneration
        var count = 0; var page: String?
        repeat {
            var params = ["q": query, "maxResults": "500", "includeSpamTrash": "true"]
            if let page { params["pageToken"] = page }
            let response = try await request("messages", query: params, labelIDs: Self.requiredLabels(query))
            count += (response["messages"] as? [[String: Any]] ?? []).count
            page = response["nextPageToken"] as? String
        } while page != nil
        if countGeneration == generation { countCache[query] = (Date(), count) }
        return count
    }
    func profileHistory() async throws -> String? { try await request("profile")["historyId"] as? String }
    func changes(since historyID: String, cachedIDs: Set<String>) async throws -> ([MailMessage], Set<String>, String?) {
        var changed = Set<String>(); var deleted = Set<String>(); var page: String?; var newest: String?
        repeat {
            var params = ["startHistoryId": historyID, "maxResults": "500"]
            if let page { params["pageToken"] = page }
            let json = try await request("history", query: params); newest = json["historyId"] as? String
            for h in json["history"] as? [[String: Any]] ?? [] {
                invalidateCounts()
                for key in ["labelsAdded", "labelsRemoved"] {
                    for value in h[key] as? [[String: Any]] ?? [] {
                        if let message = value["message"] as? [String: Any], let id = message["id"] as? String, cachedIDs.contains(id) { changed.insert(id) }
                    }
                }
                for value in h["messages"] as? [[String: Any]] ?? [] { if let id = value["id"] as? String, cachedIDs.contains(id) { changed.insert(id) } }
                for value in h["messagesAdded"] as? [[String: Any]] ?? [] { if let m = value["message"] as? [String: Any], let id = m["id"] as? String { changed.insert(id) } }
                for value in h["messagesDeleted"] as? [[String: Any]] ?? [] { if let m = value["message"] as? [String: Any], let id = m["id"] as? String { deleted.insert(id) } }
            }
            page = json["nextPageToken"] as? String
        } while page != nil
        var result: [MailMessage] = []
        for id in changed.subtracting(deleted) { result.append(try await message(id)) }
        return (result, deleted, newest)
    }
    func message(_ id: String) async throws -> MailMessage { try Self.parseMessage(await request("messages/\(id)", query: ["format": "full"])) }
    func thread(_ id: String, cached: [MailMessage] = [], loadImages: Bool = true) async throws -> [MailMessage] {
        let values: [MailMessage]
        if let existing = threadRequests[id] { values = try await existing.value }
        else {
            let task = Task { let json = try await self.request("threads/\(id)", query: ["format": "full"]); return try (json["messages"] as? [[String: Any]] ?? []).map(Self.parseMessage) }
            threadRequests[id] = task
            do { values = try await task.value; threadRequests[id] = nil }
            catch { threadRequests[id] = nil; throw error }
        }
        if !loadImages { return values.sorted { $0.date < $1.date } }
        return try await hydrateInlineImages(values, cached: cached)
    }
    func hydrateInlineImages(_ input: [MailMessage], cached: [MailMessage] = []) async throws -> [MailMessage] {
        var values = input
        let cachedMap = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        values = try await withThrowingTaskGroup(of: MailMessage.self) { group in
            for value in values { group.addTask {
                var message = value
                message.resolveInlineImages(reusing: cachedMap[message.id])
                for j in message.attachments.indices {
                    let item = message.attachments[j]
                    guard let cid = item.contentID, message.html.contains("cid:" + cid) else { continue }
                    if let bytes = try? await self.attachment(messageID: message.id, attachment: item) {
                        message.attachments[j].data = bytes
                        message.html = message.html.replacingOccurrences(of: "cid:" + cid, with: "data:" + item.mimeType + ";base64," + bytes.base64EncodedString())
                    }
                }
                return message
            } }
            var result: [MailMessage] = []; for try await value in group { result.append(value) }; return result
        }
        return values.sorted { $0.date < $1.date }
    }
    func invalidateCounts() { countGeneration = UUID(); countCache = [:]; folderCache = nil }
    func modify(_ change: PendingChange) async throws {
        invalidateCounts()
        defer { invalidateCounts() }
        var add = change.add; var remove = change.remove
        if add.contains("TRASH") {
            _ = try await request("messages/\(change.messageID)/trash", method: "POST")
            add.removeAll { $0 == "TRASH" }; remove.removeAll { $0 == "INBOX" }
        } else if remove.contains("TRASH") {
            _ = try await request("messages/\(change.messageID)/untrash", method: "POST")
            remove.removeAll { $0 == "TRASH" }
        }
        if !add.isEmpty || !remove.isEmpty {
            _ = try await request("messages/\(change.messageID)/modify", method: "POST", body: ["addLabelIds": add, "removeLabelIds": remove])
        }
    }
    func createLabel(_ name: String) async throws -> MailFolder {
        folderCache = nil
        let json = try await request("labels", method: "POST", body: ["name": name, "labelListVisibility": "labelShow", "messageListVisibility": "show"])
        guard let id = json["id"] as? String else { throw MailError.message("Google did not create the label.") }
        return .init(id: id, name: name, icon: "tag", query: "label:\"\(name)\"", isCustom: true)
    }
    func attachment(messageID: String, attachment: MailAttachment) async throws -> Data {
        if let data = attachment.data { return data }
        let key = messageID + "/" + attachment.id
        if let existing = attachmentRequests[key] { return try await existing.value }
        let task = Task<Data, Error> {
            let json = try await self.request("messages/\(messageID)/attachments/\(attachment.id)")
            guard let encoded = json["data"] as? String, let data = Data(base64URL: encoded) else { throw MailError.message("The attachment could not be downloaded.") }
            return data
        }
        attachmentRequests[key] = task
        defer { attachmentRequests.removeValue(forKey: key) }
        return try await task.value
    }
    func send(_ draft: ComposeDraft) async throws -> MailMessage {
        let address = try await accountAddress()
        let data = try MIMEBuilder.build(draft, from: address)
        var body: [String: Any] = ["raw": data.base64URL]
        if let id = draft.threadID { body["threadId"] = id }
        let json = try await request("messages/send", method: "POST", body: body)
        guard let id = json["id"] as? String else { throw MailError.message("Google did not confirm sending. Check Sent before retrying.") }
        if let fetched = try? await message(id) { return fetched }
        return MailMessage(id: id, threadID: json["threadId"] as? String ?? id, from: address, to: draft.to, cc: draft.cc, subject: draft.subject, snippet: String(draft.body.prefix(160)), body: draft.body, date: Date(), labels: ["SENT"], attachments: draft.attachments)
    }
    func saveDraft(_ draft: ComposeDraft) async throws -> String {
        let address = try await accountAddress()
        let data = try MIMEBuilder.build(draft, from: address)
        var message: [String: Any] = ["raw": data.base64URL]
        if let id = draft.threadID { message["threadId"] = id }
        let path = draft.gmailDraftID.map { "drafts/\($0)" } ?? "drafts"
        let json = try await request(path, method: draft.gmailDraftID == nil ? "POST" : "PUT", body: ["message": message])
        guard let id = json["id"] as? String else { throw MailError.message("The draft could not be saved to Gmail.") }; return id
    }
    func deleteDraft(_ id: String) async throws { _ = try await request("drafts/\(id)", method: "DELETE") }
    func drafts() async throws -> [ComposeDraft] {
        let json = try await request("drafts", query: ["maxResults": "100"])
        var result: [ComposeDraft] = []
        for row in json["drafts"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? String else { continue }
            let full = try await request("drafts/\(id)", query: ["format": "full"])
            guard let m = full["message"] as? [String: Any] else { continue }
            let message = try Self.parseMessage(m)
            result.append(.init(id: id, gmailDraftID: id, to: message.to, cc: message.cc, bcc: message.bcc ?? "", subject: message.subject, body: message.body, threadID: message.threadID, attachments: message.attachments, updated: message.date))
        }
        return result
    }
    static func parseMessage(_ json: [String: Any]) throws -> MailMessage {
        guard let id = json["id"] as? String else { throw MailError.message("An email was missing its identifier.") }
        let p = json["payload"] as? [String: Any] ?? [:]
        let headers = Dictionary((p["headers"] as? [[String: String]] ?? []).compactMap { h -> (String, String)? in guard let n = h["name"], let v = h["value"] else { return nil }; return (n.lowercased(), v) }, uniquingKeysWith: { _, b in b })
        var text = ""; var html = ""; var attachments: [MailAttachment] = []
        func walk(_ part: [String: Any]) {
            let type = part["mimeType"] as? String ?? "text/plain"
            let name = part["filename"] as? String ?? ""
            let body = part["body"] as? [String: Any] ?? [:]
            let data = (body["data"] as? String).flatMap { Data(base64URL: $0) }
            let partHeaders = part["headers"] as? [[String: String]] ?? []
            let cid = partHeaders.first { $0["name"]?.lowercased() == "content-id" }?["value"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            let disposition = partHeaders.first { $0["name"]?.lowercased() == "content-disposition" }?["value"]?.lowercased() ?? ""
            if type == "text/plain", let data, !disposition.hasPrefix("attachment") { text += String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "" }
            else if type == "text/html", let data, !disposition.hasPrefix("attachment") { html += String(data: data, encoding: .utf8) ?? "" }
            else if !name.isEmpty || cid != nil || disposition.hasPrefix("attachment") { attachments.append(.init(id: body["attachmentId"] as? String ?? UUID().uuidString, name: name.isEmpty ? "Inline image" : name, mimeType: type, size: body["size"] as? Int ?? 0, data: data, messageID: id, contentID: cid)) }
            for child in part["parts"] as? [[String: Any]] ?? [] { walk(child) }
        }
        walk(p)
        if text.isEmpty { text = json["snippet"] as? String ?? "" }
        let milliseconds = Double(json["internalDate"] as? String ?? "") ?? Date().timeIntervalSince1970 * 1000
        return .init(id: id, threadID: json["threadId"] as? String ?? id, from: headers["from"] ?? "Unknown sender", to: headers["to"] ?? "", cc: headers["cc"] ?? "", bcc: headers["bcc"] ?? "", replyTo: headers["reply-to"] ?? "", subject: headers["subject"] ?? "(No subject)", snippet: json["snippet"] as? String ?? String(text.prefix(160)), body: text, html: html, date: Date(timeIntervalSince1970: milliseconds / 1000), labels: Set(json["labelIds"] as? [String] ?? []), attachments: attachments, rfcMessageID: headers["message-id"] ?? "", references: headers["references"] ?? "")
    }
}
