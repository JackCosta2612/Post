import Foundation

final class MockProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (Int, [String: Any]))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, value) = Self.handler(request)
        let data = try! JSONSerialization.data(withJSONObject: value)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct GmailTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) { checks += 1; if !value { fatalError("FAILED: \(name)") } }
        check(NewMailSound.filename(for: nil) == "Submarine.aiff", "Existing preferences default to Submerge")
        check(NewMailSound.filename(for: "default") == nil, "System default sound remains selectable")
        check(NewMailSound.filename(for: "Glass") == "Glass.aiff", "Selected sound maps to its macOS audio file")
        let bodyPart: [String: Any] = ["mimeType": "text/html", "headers": [["name": "Content-ID", "value": "<body-html>"]], "body": ["data": Data("<p>LinkedIn-style body</p>".utf8).base64URL]]
        let parsedBody = try GmailClient.parseMessage(["id": "mime", "payload": bodyPart])
        check(parsedBody.html == "<p>LinkedIn-style body</p>" && parsedBody.attachments.isEmpty, "HTML with Content-ID is rendered as a body, not an image attachment")
        var attached = bodyPart; attached["filename"] = "document.html"; attached["headers"] = [["name": "Content-Disposition", "value": "attachment; filename=document.html"]]
        let parsedAttachment = try GmailClient.parseMessage(["id": "mime-file", "payload": attached])
        check(parsedAttachment.html.isEmpty && parsedAttachment.attachments.count == 1, "An explicit HTML file attachment remains an attachment")
        let rewritten = MessageHTML.cachedImageURLs("<img src='https://images.example/a.png'><a href='https://example.com'>Link</a><div style=\"background-image:url(https://images.example/b.png)\"></div>")
        check(rewritten.contains("src='post-image://https/images.example/a.png'") && rewritten.contains("url(post-image://https/images.example/b.png)"), "Remote image and CSS background URLs use the shared cache")
        check(rewritten.contains("href='https://example.com'"), "Image rewriting leaves external links unchanged")
        check(MessageHTML.originalImageURL(URL(string: "post-image://https/images.example/a.png?x=1&amp;y=2")!)?.absoluteString == "https://images.example/a.png?x=1&y=2", "Cached image requests restore the original URL")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        let client = GmailClient(session: session, client: .init(clientID: "test.apps.googleusercontent.com", clientSecret: "test"), token: .init(access: "test-access", refresh: "test-refresh", expiry: Date().addingTimeInterval(3600)), restore: false)
        MockProtocol.handler = { request in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access" else { return (401, ["error": ["message": "Missing token"]]) }
            let path = request.url!.path
            if path.hasSuffix("/messages") {
                let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let page = params.first { $0.name == "pageToken" }?.value
                return page == nil ? (200, ["messages": [["id": "m1"]], "nextPageToken": "page2"]) : (200, ["messages": [["id": "m2"]]])
            }
            if path.hasSuffix("/trash") { return (200, ["id": "m1", "labelIds": ["TRASH"]]) }
            if path.hasSuffix("/modify") { return (200, ["id": "m1", "labelIds": ["TRASH"]]) }
            if path.contains("/attachments/") { return (200, ["data": Data("file data".utf8).base64URL]) }
            if path.hasSuffix("/messages/m1") || path.hasSuffix("/messages/m2") {
                return (200, ["id": path.hasSuffix("m1") ? "m1" : "m2", "threadId": "t1", "internalDate": "1000", "labelIds": ["INBOX", "UNREAD"], "payload": ["mimeType": "text/plain", "headers": [["name": "Subject", "value": "Test mail"]], "body": ["data": Data("Message body".utf8).base64URL]]])
            }
            return (403, ["error": ["message": "Access denied for this test"]])
        }
        let (messages, next) = try await client.list(query: "in:inbox category:primary")
        check(messages.count == 1 && messages[0].body == "Message body", "List fetches full MIME messages")
        check(next == "page2", "Pagination token retained")
        let count = try await client.count(query: "in:inbox is:unread")
        check(count == 2, "Counts exhaust pagination instead of trusting estimates")
        try await client.modify(.init(messageID: "m1", add: ["TRASH"], remove: ["INBOX"]))
        check(true, "Label mutation completes")
        let attachment = try await client.attachment(messageID: "m1", attachment: .init(id: "a1", name: "file.txt", mimeType: "text/plain", size: 9))
        check(attachment == Data("file data".utf8), "Attachment bytes decoded")
        do { _ = try await client.request("forbidden"); fatalError("Expected HTTP error") } catch { check(error.localizedDescription.contains("Access denied"), "HTTP errors reach the UI with Google's message") }
        var operations: [String] = []
        MockProtocol.handler = { request in
            operations.append(request.url!.lastPathComponent)
            return (200, [:])
        }
        try await client.modify(.init(messageID: "m1", add: ["TRASH"], remove: ["INBOX"]))
        check(operations == ["trash"], "Delete calls the dedicated Trash endpoint")
        operations = []
        try await client.modify(.init(messageID: "m1", add: ["INBOX"], remove: ["TRASH"]))
        check(operations == ["untrash", "modify"], "Undo restores from Trash before applying inbox labels")
        let payload: [String: Any] = ["id": "inline", "payload": ["mimeType": "multipart/related", "parts": [
            ["mimeType": "text/html", "body": ["data": Data("<img src=\"cid:logo\">".utf8).base64URL]],
            ["mimeType": "image/png", "headers": [["name": "Content-ID", "value": "<logo>"]], "body": ["attachmentId": "image", "size": 3]]
        ]]]
        let parsed = try GmailClient.parseMessage(payload)
        check(parsed.attachments.first?.contentID == "logo", "Inline images without filenames retain Content-ID")
        var imageDownloads = 0
        MockProtocol.handler = { request in
            if request.url!.path.contains("/attachments/") { imageDownloads += 1; return (200, ["data": Data([1,2,3]).base64URL]) }
            return (200, ["messages": [payload]])
        }
        let rendered = try await client.thread("inline")
        check(rendered.first?.html.contains("data:image/png;base64,AQID") == true, "Embedded image references resolve to local bytes")
        _ = try await client.thread("inline", cached: rendered)
        check(imageDownloads == 1, "Previously downloaded embedded images are reused")
        let refreshed = GmailClient(session: session, client: .init(clientID: "test.apps.googleusercontent.com", clientSecret: "test"), token: .init(access: "expired", refresh: "refresh", expiry: .distantPast), restore: false)
        MockProtocol.handler = { request in
            if request.url!.host == "oauth2.googleapis.com" { return (200, ["access_token": "new-access", "expires_in": 3600]) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" ? (200, ["historyId": "99"]) : (401, [:])
        }
        let history = try await refreshed.profileHistory()
        check(history == "99", "Expired token refreshes before API request")
        let disconnected = GmailClient(session: session, restore: false)
        do { _ = try await disconnected.request("profile"); fatalError("Expected sign-in error") } catch { check(error.localizedDescription.contains("Connect Gmail"), "Disconnected client cannot mutate mail") }
        let missingClient = GmailClient(session: session, token: .init(access: "test", refresh: "test", expiry: .distantFuture), restore: false)
        let missingState = await missingClient.connectionState()
        check(!missingState.1, "A token without client configuration does not show Connected")
        let friendClient = GmailClient(session: session, client: .init(clientID: "test", clientSecret: "test"), token: .init(access: "test", refresh: "test", expiry: .distantFuture), restore: false)
        MockProtocol.handler = { _ in (200, ["emailAddress": "friend@example.com"]) }
        let friendAddress = try await friendClient.accountAddress()
        check(friendAddress == "friend@example.com", "Sender identity comes from the connected mailbox")
        let oldToken = try JSONDecoder().decode(OAuthToken.self, from: Data("{\"access\":\"test\",\"refresh\":\"test\",\"expiry\":123}".utf8))
        check(oldToken.email == nil, "Existing sign-in tokens remain compatible")
        var detailCalls = 0
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/messages") { return (200, ["messages": [["id": "m1"]]]) }
            detailCalls += 1; return (500, [:])
        }
        let (reused, _) = try await client.list(query: "in:inbox", cached: messages)
        check(reused.count == 1 && detailCalls == 0, "Unchanged message bodies are reused without get requests")
        check(GmailClient.quotaCost("messages/m1", method: "GET") == 20 && GmailClient.quotaCost("messages/send", method: "POST") == 100, "Pacing accounts for Gmail method costs")
        let limited = GmailClient(session: session, client: .init(clientID: "test", clientSecret: "test"), token: .init(access: "test-access", refresh: "test-refresh", expiry: Date().addingTimeInterval(3600)), restore: false)
        var quotaCalls = 0
        MockProtocol.handler = { _ in quotaCalls += 1; return (403, ["error": ["message": "Quota exceeded for quota metric Total Query Cost"]]) }
        do { _ = try await limited.request("profile"); fatalError("Expected quota error") } catch MailError.rateLimited { check(true, "Quota error is recognized") }
        do { _ = try await limited.request("profile"); fatalError("Expected cooldown") } catch MailError.rateLimited { check(quotaCalls == 1, "Cooldown suppresses further network requests") }
        MockProtocol.handler = { _ in return (200, ["messages": [["id": "x"]]]) }
        let counted = GmailClient(session: session, client: .init(clientID: "test", clientSecret: "test"), token: .init(access: "test-access", refresh: "test-refresh", expiry: Date().addingTimeInterval(3600)), restore: false)
        var countCalls = 0
        MockProtocol.handler = { _ in countCalls += 1; return (200, ["messages": [["id": "x"]]]) }
        _ = try await counted.count(query: "is:unread"); _ = try await counted.count(query: "is:unread")
        check(countCalls == 1, "Repeated folder counts reuse their cached result")
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/history") {
                return (200, ["historyId": "2", "history": [["labelsRemoved": [["message": ["id": "x"], "labelIds": ["INBOX", "UNREAD"]]]]]])
            }
            if request.url!.path.hasSuffix("/messages/x") {
                return (200, ["id": "x", "threadId": "t", "labelIds": [], "payload": ["mimeType": "text/plain", "body": ["data": Data("body".utf8).base64URL]]])
            }
            countCalls += 1; return (200, ["messages": []])
        }
        let (changedLabels, _, _) = try await counted.changes(since: "1", cachedIDs: ["x"])
        check(changedLabels.count == 1 && !changedLabels[0].unread, "Label-only history events refresh cached message state")
        let correctedCount = try await counted.count(query: "is:unread")
        check(correctedCount == 0 && countCalls == 2, "History changes invalidate unread counts immediately")
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/modify") { return (200, [:]) }
            countCalls += 1; return (200, ["messages": [["id": "x"]]])
        }
        try await counted.modify(.init(messageID: "x", add: ["INBOX"], remove: []))
        let restoredCount = try await counted.count(query: "is:unread")
        check(restoredCount == 1 && countCalls == 3, "Completed label changes discard earlier count snapshots")
        let visibleCounts = GmailClient(session: session, client: .init(clientID: "test", clientSecret: "test"), token: .init(access: "test", refresh: "test", expiry: .distantFuture), restore: false)
        MockProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/labels") { return (200, ["labels": []]) }
            if path.hasSuffix("/messages") {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems?.first { $0.name == "q" }?.value ?? ""
                return (200, query.contains("-in:trash") && query.contains("-in:spam") ? ["messages": []] : ["messages": [["id": "trashed-promotion"]]])
            }
            return (200, ["messagesUnread": 1, "messagesTotal": 1])
        }
        let visibleFolders = try await visibleCounts.folders()
        let promotions = visibleFolders.first { $0.id == "CATEGORY_PROMOTIONS" }!
        check(promotions.unreadCount == 0 && promotions.totalCount == 0, "Promotions badges exclude messages retained in Trash and Spam")
        var threadCalls = 0
        var inlineCalls = 0
        MockProtocol.handler = { request in
            if request.url!.path.contains("/attachments/") { inlineCalls += 1; return (200, ["data": Data("image".utf8).base64URL]) }
            threadCalls += 1
            Thread.sleep(forTimeInterval: 0.05)
            return (200, ["messages": [["id": "body-first", "threadId": "conversation", "payload": ["mimeType": "multipart/related", "parts": [["mimeType": "text/html", "body": ["data": Data("<p>Hello</p><img src=\"cid:image\">".utf8).base64URL]], ["mimeType": "image/png", "headers": [["name": "Content-ID", "value": "<image>"]], "body": ["attachmentId": "inline-image"]]]]]]])
        }
        async let firstThread = client.thread("conversation", loadImages: false)
        async let secondThread = client.thread("conversation", loadImages: false)
        let bodies = try await (firstThread, secondThread)
        check(threadCalls == 1, "Concurrent opens share one conversation request")
        check(inlineCalls == 0 && bodies.0[0].html.contains("Hello"), "Conversation bodies load without waiting for inline images")
        let hydrated = try await client.hydrateInlineImages(bodies.0)
        check(inlineCalls == 1 && hydrated[0].html.contains("data:image/png"), "Inline media loads independently after conversation text")
        _ = try await client.hydrateInlineImages(bodies.0, cached: hydrated)
        check(inlineCalls == 1, "Cached inline media avoids another download")
        print("PASS: \(checks) Gmail integration checks with simulated responses")
    }
}
