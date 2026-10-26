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

public enum SleepBlockerSummary {
    // These macOS services hold housekeeping/display/session assertions, rather than
    // identifying a user action. Keep this display-only list short; extend it here.
    private static let internalProcesses: Set<String> = [
        "powerd", "WindowServer", "loginwindow", "sharingd",
    ]

    public static func names(
        assertions: [SleepAssertion], ownPID: Int32, showOtherSleepBlockers: Bool = false
    ) -> [String] {
        let names = assertions.compactMap { assertion -> String? in
            guard assertion.pid != ownPID else { return nil }
            guard assertion.isCaffeinate || showOtherSleepBlockers else { return nil }
            return displayName(for: assertion.processName)
        }
        let sorted = Array(Set(names)).sorted()
        guard sorted.count > 3 else { return sorted }
        return Array(sorted.prefix(3)) + ["+\(sorted.count - 3) more"]
    }

    public static let ownKeepAwakeName = "the app's own keep-awake"

    public static let ownKeepUnlockedName = "the app's own keep-unlocked (display kept awake)"

    static func alertNames(_ names: [String]) -> [String] {
        names.filter { $0 == "caffeinate" || $0 == ownKeepAwakeName || $0 == ownKeepUnlockedName }
    }

    static func displayName(for processName: String) -> String? {
        guard !processName.isEmpty, !internalProcesses.contains(processName) else { return nil }
        return processName == "coreaudiod" ? "audio playback" : processName
    }
}
