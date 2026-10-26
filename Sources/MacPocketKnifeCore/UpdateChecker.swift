// Copyright 2026 Francisco Perdigon Romero and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// Asks GitHub which release the app should update to, for the chosen channel.
public protocol UpdateChecking: Sendable {
    func check(channel: UpdateChannel, build: BuildInfo) async throws -> UpdateCheckResult
}

public struct UpdateChecker: UpdateChecking {
    /// Performs a request and returns the body and HTTP status. Injected so tests need no network.
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let defaultRepo = "fperdigon/macpocketknife"

    public enum CheckError: LocalizedError, Equatable {
        case rateLimited
        case http(Int)
        case invalidResponse
        case noRelease(UpdateChannel)
        case noAsset(String)

        public var errorDescription: String? {
            switch self {
            case .rateLimited: return "GitHub is limiting requests from this network. Try again later."
            case .http(let code): return "GitHub answered with HTTP \(code)."
            case .invalidResponse: return "Unexpected response from GitHub."
            case .noRelease(let ch): return "No \(ch == .stable ? "stable release" : "nightly build") has been published yet."
            case .noAsset(let tag): return "Release \(tag) has no download for MacPocketKnife."
            }
        }
    }

    private let fetch: Fetch

    public init(fetch: @escaping Fetch = UpdateChecker.urlSessionFetch) {
        self.fetch = fetch
    }

    public static let urlSessionFetch: Fetch = { request in
        let session = URLSession(configuration: .ephemeral, delegate: GitHubAPIRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func check(channel: UpdateChannel, build: BuildInfo) async throws -> UpdateCheckResult {
        switch channel {
        case .stable: return try await checkStable(build)
        case .nightly: return try await checkNightly(build)
        }
    }

    // MARK: - Channels

    private func checkStable(_ build: BuildInfo) async throws -> UpdateCheckResult {
        let data = try await get("/repos/\(Self.defaultRepo)/releases/latest", channel: .stable)
        let release = try decode(ReleaseInfo.self, data)
        guard !release.draft, !release.prerelease else { throw CheckError.noRelease(.stable) }
        guard VersionCompare.compare(build.version, release.version) < 0 else {
            return .upToDate(current: build.version)
        }
        return .available(try makeUpdate(release, channel: .stable, label: release.version))
    }

    private func checkNightly(_ build: BuildInfo) async throws -> UpdateCheckResult {
        var releases: [ReleaseInfo] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let data = try await get("/repos/\(Self.defaultRepo)/releases?per_page=100&page=\(page)", channel: .nightly)
            let batch = try decode([ReleaseInfo].self, data)
            releases.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
        }
        let nightlies = releases
            .filter { !$0.draft && $0.prerelease && $0.tag.hasPrefix("nightly-") }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        guard let newest = nightlies.first else { throw CheckError.noRelease(.nightly) }
        if !build.isDevBuild, let sha = Self.nightlySHA(of: newest), build.sha.lowercased().hasPrefix(sha) {
            return .upToDate(current: "nightly \(build.shortSHA)")
        }
        return .available(try makeUpdate(newest, channel: .nightly, label: Self.nightlyLabel(of: newest)))
    }

    // MARK: - Helpers

    /// The 7-character commit suffix of a `nightly-YYYYMMDD-<sha>` tag.
    public static func nightlySHA(of release: ReleaseInfo) -> String? {
        guard release.tag.hasPrefix("nightly-"), let last = release.tag.split(separator: "-").last,
              last.count == 7, last.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return String(last).lowercased()
    }

    /// "Nightly 2026-10-16 (abc1234)" from a `nightly-YYYYMMDD-<sha>` tag, because the release
    /// title is just "Nightly". Falls back to the release name for other tags.
    public static func nightlyLabel(of release: ReleaseInfo) -> String {
        let parts = release.tag.split(separator: "-")
        guard parts.count == 3, parts[0] == "nightly", parts[1].count == 8, parts[1].allSatisfy({ $0.isNumber }),
              let sha = nightlySHA(of: release) else { return release.name }
        let d = parts[1]
        return "Nightly \(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2)) (\(sha.prefix(7)))"
    }

    public static func selectAsset(_ assets: [ReleaseAsset]) -> ReleaseAsset? {
        assets.first {
            $0.name.hasPrefix("MacPocketKnife-") && $0.name.hasSuffix(".dmg")
                && !$0.name.contains("/") && !$0.name.contains("\\")
                && $0.downloadURL.scheme == "https" && $0.downloadURL.host == "github.com"
                && $0.downloadURL.path.hasPrefix("/fperdigon/macpocketknife/releases/download/")
        }
    }

    private func makeUpdate(_ release: ReleaseInfo, channel: UpdateChannel, label: String) throws -> AvailableUpdate {
        guard let asset = Self.selectAsset(release.assets) else {
            throw CheckError.noAsset(release.tag)
        }
        return AvailableUpdate(channel: channel, release: release, asset: asset, label: label)
    }

    private func get(_ path: String, channel: UpdateChannel) async throws -> Data {
        guard let url = URL(string: "https://api.github.com" + path) else { throw CheckError.invalidResponse }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("macpocketknife-updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, status) = try await fetch(req)
        switch status {
        case 200: return data
        case 404: throw CheckError.noRelease(channel)
        case 403, 429: throw CheckError.rateLimited
        default: throw CheckError.http(status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw CheckError.invalidResponse }
    }
}

private final class GitHubAPIRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "api.github.com" ? request : nil)
    }
}
