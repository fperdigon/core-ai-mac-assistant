// Copyright 2026 The Core AI Mac Assistant contributors
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

public enum StatusLineFormatter {
    public static func format(
        power: PowerState, estimate: BatteryEstimate
    ) -> String {
        let battery = power.batteryPercent.map { "Battery \($0)%" } ?? "Battery unknown"
        let source = power.isCharging ? "charging" : (power.source == .battery ? "on battery" : "plugged in")
        var parts = [battery, source]
        if power.source == .battery || power.isCharging {
            if let duration = duration(estimate.timeRemaining) {
                parts.append(duration + (power.isCharging ? " to full" : " left"))
            } else {
                parts.append("estimating…")
            }
            if let watts = estimate.powerWatts, watts.isFinite, watts > 0 {
                parts.append(String(format: "%.1f W", locale: Locale(identifier: "en_US_POSIX"), watts))
            }
        }
        return parts.joined(separator: " · ")
    }

    public static func blockersLine(blockers: [String]) -> String? {
        guard !blockers.isEmpty else { return nil }
        return "Also keeping awake: " + blockers.joined(separator: ", ")
    }

    public static func duration(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 60 { return "<1m" }
        let minutes = (seconds / 60).rounded(.down)
        guard minutes < Double(Int.max) else { return nil }
        let total = Int(minutes)
        if total < 60 { return "\(total)m" }
        return "\(total / 60)h " + String(format: "%02dm", total % 60)
    }

    static func alertEstimate(_ estimate: BatteryEstimate) -> String {
        guard let duration = duration(estimate.timeRemaining) else { return "" }
        return ", about \(duration) left"
    }
}
