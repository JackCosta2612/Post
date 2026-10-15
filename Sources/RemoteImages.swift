import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

struct RemoteImage: Codable {
    let data: Data
    let mimeType: String
    static func validated(_ data: Data, mimeType: String?) throws -> RemoteImage {
        guard !data.isEmpty, data.count <= 25 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) {
            let formats = ["public.png":"image/png", "public.jpeg":"image/jpeg", "com.compuserve.gif":"image/gif", "public.tiff":"image/tiff", "org.webmproject.webp":"image/webp", "public.webp":"image/webp", "public.avif":"image/avif", "public.heic":"image/heic", "com.microsoft.bmp":"image/bmp", "com.microsoft.ico":"image/x-icon"]
            if let mime = formats[type as String] ?? UTType(type as String)?.preferredMIMEType ?? mimeType.flatMap({ $0.hasPrefix("image/") ? $0 : nil }) {
                return RemoteImage(data: data, mimeType: mime)
            }
        }
        let prefix = String(decoding: data.prefix(65536), as: UTF8.self).lowercased()
        if prefix.contains("<svg"), !prefix.contains("<html") { return RemoteImage(data: data, mimeType: "image/svg+xml") }
        throw URLError(.cannotDecodeContentData)
    }
}
private final class ImageMemoryEntry: NSObject {
    let value: RemoteImage
    init(_ value: RemoteImage) { self.value = value }
}

// Networking, validation and disk-cache access run outside the main actor.
actor RemoteImagePipeline {
    private let session: URLSession
    private let directory: URL?
    private let diskLimit: Int
    private var diskUsage: Int?
    private struct DiskEntry: Codable { let saved: Date; let image: RemoteImage }
    private let memory = NSCache<NSURL, ImageMemoryEntry>()
    private var downloads: [URL: Task<RemoteImage, Error>] = [:]
    private var active = 0
    private var waiting: [(Bool, CheckedContinuation<Void, Never>)] = []
    private var generation = 0
    init(mode: String = "balanced", directory: URL? = nil, configuration: URLSessionConfiguration? = nil) {
        let fast = mode == "fast"
        self.directory = directory?.appendingPathComponent("RemoteImages-v2")
        self.diskLimit = (fast ? 1024 : 128) * 1024 * 1024
        let config = configuration ?? URLSessionConfiguration.default
        // Own cache writes explicitly, after validation. URLSession must not
        // cache error pages or finish an automatic write after Clear Cache.
        config.urlCache = nil
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 40
        self.session = URLSession(configuration: config)
        memory.totalCostLimit = (fast ? 128 : 32) * 1024 * 1024
    }
    private func acquire(prefetch: Bool) async {
        if active < 6 { active += 1; return }
        await withCheckedContinuation { waiting.append((prefetch, $0)) }
    }
    private func release() {
        if waiting.isEmpty { active -= 1; return }
        let index = waiting.firstIndex { !$0.0 } ?? 0
        waiting.remove(at: index).1.resume()
    }
    func image(_ url: URL, prefetch: Bool = false) async throws -> RemoteImage {
        let original = MessageHTML.secureImageURL(url)
        if let hit = memory.object(forKey: original as NSURL) { return hit.value }
        if let task = downloads[original] { return try await task.value }
        let revision = generation
        let task = Task<RemoteImage, Error>(priority: prefetch ? .utility : .userInitiated) {
            await self.acquire(prefetch: prefetch)
            defer { self.release() }
            try Task.checkCancellation()
            var request = URLRequest(url: original, cachePolicy: .returnCacheDataElseLoad)
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            if let saved = self.readDisk(original) { return saved }
            request.cachePolicy = .reloadIgnoringLocalCacheData
            for attempt in 0..<3 {
                do {
                    let (data, response) = try await self.session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if [408, 429, 500, 502, 503, 504].contains(http.statusCode), attempt < 2 {
                        let delay = min(max(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0.3 * Double(attempt + 1), 0.3), 3)
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)); continue
                    }
                    guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                    let image = try RemoteImage.validated(data, mimeType: response.mimeType)
                    if self.generation == revision {
                        self.writeDisk(image, url: original)
                    }
                    return image
                } catch {
                    let transient = [URLError.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                    guard attempt < 2, let error = error as? URLError, transient.contains(error.code) else { throw error }
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 300_000_000)
                }
            }
            throw URLError(.badServerResponse)
        }
        downloads[original] = task
        do {
            let result = try await task.value
            if generation == revision {
                memory.setObject(ImageMemoryEntry(result), forKey: original as NSURL, cost: result.data.count)
                downloads.removeValue(forKey: original)
            }
            return result
        } catch {
            if generation == revision { downloads.removeValue(forKey: original) }
            throw error
        }
    }
    private func file(_ url: URL) -> URL? {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name + ".json")
    }
    private func readDisk(_ url: URL) -> RemoteImage? {
        if diskUsage == nil { trimDisk() }
        guard let file = file(url), let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(DiskEntry.self, from: data),
              Date().timeIntervalSince(entry.saved) < 30 * 86400,
              let image = try? RemoteImage.validated(entry.image.data, mimeType: entry.image.mimeType) else { return nil }
        return image
    }
    private func writeDisk(_ image: RemoteImage, url: URL) {
        guard let directory, let file = file(url), let data = try? JSONEncoder().encode(DiskEntry(saved: Date(), image: image)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if diskUsage == nil { trimDisk() }
        let previous = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do { try data.write(to: file, options: .atomic) } catch { return }
        diskUsage = (diskUsage ?? 0) + data.count - previous
        if (diskUsage ?? 0) > diskLimit { trimDisk() }
    }

    private func trimDisk() {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > diskLimit {
            try? FileManager.default.removeItem(at: entry.0); total -= entry.1
        }
        diskUsage = total
    }
    func clear() {
        generation += 1
        for task in downloads.values { task.cancel() }
        downloads.removeAll(); memory.removeAllObjects(); diskUsage = 0
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}
