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

public protocol TelegramAlertFormatting: Sendable {
    func format(
        alert: BatteryAlert, blockers: [String]?, includeMachineName: String?, estimate: BatteryEstimate
    ) -> String
}

public extension TelegramAlertFormatting {
    func format(alert: BatteryAlert, blockers: [String]?, includeMachineName: String?) -> String {
        format(alert: alert, blockers: blockers, includeMachineName: includeMachineName,
               estimate: BatteryEstimate())
    }
}

public struct TelegramAlertFormatter: TelegramAlertFormatting {
    public init() {}

    public func format(
        alert: BatteryAlert, blockers: [String]? = nil, includeMachineName: String? = nil,
        estimate: BatteryEstimate = BatteryEstimate()
    ) -> String {
        let level: String
        switch alert.level {
        case .normal: level = "Normal"
        case .urgent: level = "Urgent"
        case .critical: level = "Critical"
        }
        let machine = includeMachineName.map { " (\($0))" } ?? ""
        let names = (blockers ?? []).compactMap { SleepBlockerSummary.displayName(for: $0) }
        let keepingAwake = names.isEmpty ? "an active sleep assertion" : names.joined(separator: ", ")
        let remaining = StatusLineFormatter.alertEstimate(estimate)
        return "\(level): battery at \(alert.batteryPercent)%\(machine)\(remaining). Keeping the Mac awake: \(keepingAwake)."
    }
}
