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

public struct BuildInfo: Equatable, Sendable {
    public let version: String
    public let sha: String
    public let channel: String

    public init(version: String, sha: String = "unknown", channel: String = "dev") {
        self.version = version
        self.sha = sha.count == 40 && sha.allSatisfy({ $0.isASCII && $0.isHexDigit })
            ? sha.lowercased() : "unknown"
        self.channel = ["stable", "nightly", "dev"].contains(channel) ? channel : "dev"
    }

    public init(infoDictionary: [String: Any]?, bundleIdentifier: String?) {
        self.init(
            version: infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            sha: bundleIdentifier == nil ? "unknown" : infoDictionary?["CAMGitSHA"] as? String ?? "unknown",
            channel: bundleIdentifier == nil ? "dev" : infoDictionary?["CAMBuildChannel"] as? String ?? "dev"
        )
    }

    public static var current: BuildInfo {
        BuildInfo(infoDictionary: Bundle.main.infoDictionary, bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    public var shortSHA: String { String(sha.prefix(7)) }
    public var isDevBuild: Bool { sha == "unknown" || channel == "dev" }

    /// Version text shown in the About section.
    public static func aboutVersion(version: String, sha: String, channel: String) -> String {
        guard channel == "nightly" || channel == "dev", sha != "unknown", !sha.isEmpty else {
            return version
        }
        return "\(version) (\(sha.prefix(7)))"
    }

    /// Version text shown in Settings for the running build.
    public var displayVersion: String {
        if isDevBuild { return "development build" }
        if channel == "nightly" { return "\(version) (\(shortSHA)) nightly" }
        return version
    }
}

public enum VersionCompare {
    /// Compares dotted numeric versions ("0.1.3" vs "0.2"): -1, 0 or 1. Non-numeric parts count as 0.
    public static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            let trimmed = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}
