import Foundation
import SwiftUI

struct ReleaseVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), fields.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = fields.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
@MainActor final class PostUpdates: ObservableObject {
    static let shared = PostUpdates()
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    var openAccount = false
    @Published var checking = false
    @Published var status = ""
    @Published var releaseURL: URL?
    func check() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        status = "Checking releases…"; releaseURL = nil
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/JackCosta2612/Post/releases/latest")!)
            request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 { status = "No published release yet."; return }
            guard http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, let latest = ReleaseVersion(tag), let current = ReleaseVersion(Self.version),
                  let address = json["html_url"] as? String, let url = URL(string: address), url.host == "github.com", url.path.hasPrefix("/JackCosta2612/Post/releases/") else { throw URLError(.badServerResponse) }
            if latest > current { status = "Post \(tag) is available."; releaseURL = url }
            else if current > latest { status = "You’re using a development version newer than the latest release." }
            else { status = "Post is up to date." }
        } catch { status = "Couldn’t check for updates. Try again later." }
    }
}
