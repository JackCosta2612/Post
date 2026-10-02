import Foundation
import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

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
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.3" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    @Published var notesVisible = false
    private var started = false
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif
    var automaticChecks: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyChecksForUpdates ?? true
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }
    var automaticInstallation: Bool {
        get {
            #if canImport(Sparkle)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
            #endif
        }
    }
    var releaseNotes: String {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md") ?? Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md") else { return "Post has been updated." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Post has been updated."
    }
    func start() {
        guard !started else { return }; started = true
        #if canImport(Sparkle)
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "PostLastLaunchedVersion")
        defaults.set(Self.version, forKey: "PostLastLaunchedVersion")
        if let previous, let old = ReleaseVersion(previous), let current = ReleaseVersion(Self.version), current > old {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.notesVisible = true }
        }
    }
    var openAccount = false
    @Published var checking = false
    @Published var status = ""
    @Published var releaseURL: URL?
    func check() async {
        #if canImport(Sparkle)
        if let controller { controller.checkForUpdates(nil); return }
        #endif
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

struct ReleaseNotesPane: View {
    @ObservedObject var updates = PostUpdates.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What’s new in Post \(PostUpdates.version)").font(.title2.weight(.semibold))
            ScrollView { Text(updates.releaseNotes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            HStack { Spacer(); Button("Done") { updates.notesVisible = false }.keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 520, height: 360)
    }
}
