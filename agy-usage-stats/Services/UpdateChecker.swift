//
//  UpdateChecker.swift
//  agy-usage-stats
//

import Foundation

public struct UpdateInfo {
    public let version: String          // e.g. "1.2.0" or "latest"
    public let tagName: String          // e.g. "v1.2.0" or "latest"
    public let releaseURL: URL
    public let downloadURL: URL?
    public let releaseNotes: String?
    public let isRolling: Bool          // true for the "latest" CI build
    public let publishedAt: TimeInterval?  // Unix timestamp of the release
}

public enum UpdateChecker {
    public static let githubRepo = "sameerbajaj/agy-usage-stats"
    public static let releasesPage = URL(string: "https://github.com/\(githubRepo)/releases")!

    // Returns an UpdateInfo if a newer version (or newer rolling build) is available.
    public static func check() async -> UpdateInfo? {
        #if DEBUG
        // In local debug builds, do not prompt the developer to overwrite their working copy with remote releases!
        return nil
        #endif

        if Bundle.main.bundlePath.contains("DerivedData") {
            return nil
        }

        let apiURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases")!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("agy-usage-stats", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data)
        else { return nil }

        // 1. Check stable releases first
        if let newest = releases.first(where: { !$0.draft && !$0.prerelease && $0.tagName != "latest" }) {
            let remoteVersion = normalise(newest.tagName)
            let localVersion  = normalise(currentVersion)
            if isNewer(remoteVersion, than: localVersion) {
                return UpdateInfo(
                    version: remoteVersion,
                    tagName: newest.tagName,
                    releaseURL: URL(string: newest.htmlURL) ?? releasesPage,
                    downloadURL: preferredDMGURL(in: newest),
                    releaseNotes: newest.body,
                    isRolling: false,
                    publishedAt: newest.publishedAt
                )
            }
        }

        // 2. Check the rolling "latest" release
        if let latest = releases.first(where: { $0.tagName == "latest" && !$0.draft }) {
            let localVersion = normalise(currentVersion)
            let releaseVersion = version(from: latest.name) ?? version(from: latest.body)
            let publishedAt = latest.publishedAt ?? 0
            let baseline = max(buildTimestamp, lastInstalledRollingTimestamp)
            
            // Hard invariant: if the rolling release was published at or before our installed baseline,
            // we are already running this build (or a newer build). NEVER prompt!
            if publishedAt > 0 && baseline > 0 && publishedAt <= baseline + 60 {
                return nil
            }
            
            // If remote release has a version and matches our local version exactly:
            if let remoteVersion = releaseVersion, remoteVersion == localVersion {
                return nil
            }
            
            if let remoteVersion = releaseVersion {
                if isNewer(remoteVersion, than: localVersion) {
                    // Suppress if the release timestamp is already accounted for
                    if publishedAt > 0 && baseline > 0 && publishedAt <= baseline + 60 {
                        return nil
                    }
                    return UpdateInfo(
                        version: remoteVersion,
                        tagName: "latest",
                        releaseURL: URL(string: latest.htmlURL) ?? releasesPage,
                        downloadURL: preferredDMGURL(in: latest),
                        releaseNotes: latest.body,
                        isRolling: true,
                        publishedAt: latest.publishedAt
                    )
                }
            } else if publishedAt > 0 {
                if baseline > 0 && publishedAt > baseline + 300 {
                    return UpdateInfo(
                        version: "latest",
                        tagName: "latest",
                        releaseURL: URL(string: latest.htmlURL) ?? releasesPage,
                        downloadURL: preferredDMGURL(in: latest),
                        releaseNotes: latest.body,
                        isRolling: true,
                        publishedAt: publishedAt
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    public static let lastInstalledKey = "lastInstalledRollingTimestamp"
    public static let lastInstalledVersionKey = "lastInstalledReleaseVersion"

    public static var currentVersion: String {
        let plistVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if !plistVer.isEmpty && plistVer != "latest" && plistVer != "0" {
            return plistVer
        }
        // Fall back to recorded version in UserDefaults if plist is "latest" or missing
        let recordedVer = UserDefaults.standard.string(forKey: lastInstalledVersionKey) ?? ""
        if !recordedVer.isEmpty {
            return recordedVer
        }
        return plistVer.isEmpty ? "0" : plistVer
    }

    /// CFBundleVersion is stamped as a Unix timestamp by build-dmg.sh
    public static var buildTimestamp: TimeInterval {
        guard let s = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let ts = TimeInterval(s) else { return 0 }
        return ts
    }

    // MARK: - Last-installed rolling timestamp

    /// The `published_at` of the rolling release we last self-updated to.
    /// Persisted in UserDefaults so it survives relaunch.
    public static var lastInstalledRollingTimestamp: TimeInterval {
        UserDefaults.standard.double(forKey: lastInstalledKey)
    }

    /// Call after a successful self-update from a rolling release to prevent
    /// the checker from re-detecting the same build as an update.
    public static func recordInstalledRollingTimestamp(_ publishedAt: TimeInterval, version: String? = nil) {
        UserDefaults.standard.set(publishedAt, forKey: lastInstalledKey)
        if let version, !version.isEmpty {
            UserDefaults.standard.set(version, forKey: lastInstalledVersionKey)
        }
        UserDefaults.standard.synchronize()
    }

    public static func normalise(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        return s
    }

    public static func version(from text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"(?:^|[\svV])(\d+\.\d+\.\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    public static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        // CRITICAL GUARD: Both must have parsed integers.
        // If either is empty (e.g. "latest", "unknown", or invalid string),
        // we cannot do semantic comparison.
        guard !av.isEmpty, !bv.isEmpty else { return false }
        let count = max(av.count, bv.count)
        for i in 0..<count {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }

    private static func preferredDMGURL(in release: GitHubRelease) -> URL? {
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return dmg.flatMap { URL(string: $0.browserDownloadURL) }
    }
}

// MARK: - GitHub API models

private struct GitHubRelease: Decodable {
    let tagName:     String
    let name:        String?
    let htmlURL:     String
    let draft:       Bool
    let prerelease:  Bool
    let body:        String?
    let publishedAt: TimeInterval?   // decoded from ISO-8601 string
    let assets:      [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName    = "tag_name"
        case name
        case htmlURL    = "html_url"
        case draft, prerelease, body
        case publishedAt = "published_at"
        case assets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName    = try c.decode(String.self, forKey: .tagName)
        name       = try c.decodeIfPresent(String.self, forKey: .name)
        htmlURL    = try c.decode(String.self, forKey: .htmlURL)
        draft      = try c.decode(Bool.self,   forKey: .draft)
        prerelease = try c.decode(Bool.self,   forKey: .prerelease)
        body       = try c.decodeIfPresent(String.self, forKey: .body)
        assets     = try c.decodeIfPresent([GitHubAsset].self, forKey: .assets) ?? []
        if let iso = try c.decodeIfPresent(String.self, forKey: .publishedAt) {
            let fmt = ISO8601DateFormatter()
            publishedAt = fmt.date(from: iso)?.timeIntervalSince1970
        } else {
            publishedAt = nil
        }
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
