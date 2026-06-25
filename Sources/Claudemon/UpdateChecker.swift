import Foundation
import os

/// Diagnostics logger for the update-check layer.
private let updateLog = Logger(subsystem: "com.claudemon.app", category: "UpdateChecker")

/// Notify-only "Check for Updates" against the GitHub Releases API.
///
/// Dependency-free (no Sparkle): a single HTTPS GET to the public
/// `releases/latest` endpoint, compared to the running app's
/// `CFBundleShortVersionString`. Claudemon is unsandboxed, so the network call
/// needs no entitlement. We never auto-download — we only surface a calm hint
/// and let Homebrew do the upgrade.
@MainActor
final class UpdateChecker: ObservableObject {

    /// The state machine driving the footer UI. Calm, non-alarming by design.
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(latest: String, url: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// The running app's marketing version (e.g. "1.1.2"). Falls back to "0"
    /// when no Info.plist is embedded (e.g. plain `swift build` CLI runs).
    let currentVersion: String

    init() {
        self.currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Subset of the GitHub release payload we care about.
    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// Fetch the latest published release and compare versions. Concurrent
    /// invocations are ignored while a check is in flight.
    func check() async {
        guard state != .checking else { return }
        state = .checking

        let endpoint = URL(string: "https://api.github.com/repos/ardabalkandev/claudemon/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests without a User-Agent.
        request.setValue("Claudemon/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                updateLog.error("update check got HTTP \(http.statusCode, privacy: .public)")
                state = .failed("Couldn't check for updates")
                return
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            let latestTag = release.tag_name

            guard let latest = SemVer(latestTag), let current = SemVer(currentVersion) else {
                updateLog.error("update check couldn't parse versions (latest: \(latestTag, privacy: .public), current: \(self.currentVersion, privacy: .public))")
                state = .failed("Couldn't check for updates")
                return
            }

            if latest > current {
                updateLog.info("update available: \(latest.description, privacy: .public) (current \(current.description, privacy: .public))")
                state = .updateAvailable(latest: latest.description, url: release.html_url)
            } else {
                updateLog.info("up to date at \(current.description, privacy: .public)")
                state = .upToDate(current: current.description)
            }
        } catch {
            updateLog.error("update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("Couldn't check for updates")
        }
    }
}

/// Minimal `major.minor.patch` semantic version for comparison. Tolerates a
/// leading `v` (GitHub tags like `v1.1.2`) and missing minor/patch components.
struct SemVer: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.first == "v" || string.first == "V" {
            string.removeFirst()
        }
        let parts = string.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        func component(_ index: Int) -> Int? {
            guard index < parts.count else { return 0 }
            return Int(parts[index])
        }
        guard let major = component(0), let minor = component(1), let patch = component(2) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
