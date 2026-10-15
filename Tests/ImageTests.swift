import Foundation

final class ImageProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requests: [String: Int] = [:]
    static var active = 0, peak = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return requests[path, default: 0] }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock()
        Self.requests[path, default: 0] += 1; let count = Self.requests[path]!
        Self.active += 1; Self.peak = max(Self.peak, Self.active)
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.025) {
            let status = path == "/missing" ? 404 : (path == "/retry" && count == 1 ? 503 : 200)
            let body = path == "/invalid" ? "<html>Error page</html>" : "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'><rect width='24' height='24'/></svg>"
            Self.lock.lock(); Self.active -= 1; Self.lock.unlock()
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/octet-stream", "Cache-Control":"max-age=86400"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8)); self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main struct ImageTests {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) { checks += 1; if !condition { fatalError("FAILED: " + name) } }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB1sAAAAASUVORK5CYII=")!
        check(try RemoteImage.validated(png, mimeType: "application/octet-stream").mimeType == "image/png", "PNG recognition works without the system MIME registry")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Post-ImageTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = RemoteImagePipeline(directory: directory, configuration: config)
        let base = "https://image-tests-\(UUID().uuidString).example"
        let shared = URL(string: base + "/shared")!
        async let first = pipeline.image(shared)
        async let second = pipeline.image(shared)
        let (a, b) = try await (first, second)
        check(a.data == b.data && ImageProtocol.count("/shared") == 1, "Concurrent requests share one download")
        _ = try await pipeline.image(shared)
        check(ImageProtocol.count("/shared") == 1, "Previously loaded images reuse memory without networking")
        let restartConfig = URLSessionConfiguration.ephemeral; restartConfig.protocolClasses = [ImageProtocol.self]
        let restarted = RemoteImagePipeline(directory: directory, configuration: restartConfig)
        _ = try await restarted.image(shared)
        check(ImageProtocol.count("/shared") == 1, "A fresh loader reuses the persistent image cache")
        check(a.mimeType == "image/svg+xml", "Actual image format corrects incorrect server MIME type")
        _ = try await pipeline.image(URL(string: base + "/retry")!)
        check(ImageProtocol.count("/retry") == 2, "Temporary server errors retry and recover")
        do { _ = try await pipeline.image(URL(string: base + "/missing")!); fatalError("Missing image accepted") } catch {}
        check(ImageProtocol.count("/missing") == 1, "Permanent missing files do not retry")
        for _ in 0..<2 { do { _ = try await pipeline.image(URL(string: base + "/invalid")!); fatalError("HTML accepted as image") } catch {} }
        check(ImageProtocol.count("/invalid") == 2, "Error pages never poison the image cache")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<18 { group.addTask { _ = try await pipeline.image(URL(string: base + "/bulk\(index)")!) } }
            try await group.waitForAll()
        }
        check(ImageProtocol.peak <= 6, "Image downloads have bounded concurrency")
        await pipeline.clear(); _ = try await pipeline.image(shared)
        check(ImageProtocol.count("/shared") == 2, "Clearing the cache removes memory and disk responses")
        let responsive = MessageHTML.cachedImageURLs("<img src=//cdn.example/logo.png srcset='https://cdn.example/a.png 1x, //cdn.example/b.png 2x'><div style=\"background:url(//cdn.example/bg.png)\"></div><a href='https://cdn.example/page'>Link</a>")
        check(responsive.contains("src=post-image://https/cdn.example/logo.png"), "Unquoted and protocol-relative image sources are rewritten")
        check(responsive.contains("post-image://https/cdn.example/b.png 2x"), "Responsive image candidates use the shared loader")
        check(responsive.contains("url(post-image://https/cdn.example/bg.png)"), "CSS background images use the shared loader")
        check(responsive.contains("href='https://cdn.example/page'"), "Image rewriting preserves navigation links")
        check(MessageHTML.remoteImageURLs(responsive).count == 4, "Prefetch discovers the same sources as the viewer")
        print("PASS: \(checks) image pipeline checks")
    }
}
