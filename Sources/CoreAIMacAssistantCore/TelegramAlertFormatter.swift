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

public protocol TelegramAlertFormatting: Sendable {
    func format(
        alert: BatteryAlert, blockers: [String]?, includeMachineName: String?
    ) -> String
}

public struct TelegramAlertFormatter: TelegramAlertFormatting {
    public init() {}

    public func format(
        alert: BatteryAlert, blockers: [String]? = nil, includeMachineName: String? = nil
    ) -> String {
        let level: String
        switch alert.level {
        case .normal: level = "Normal"
        case .urgent: level = "Urgent"
        case .critical: level = "Critical"
        }
        let machine = includeMachineName.map { " (\($0))" } ?? ""
        let names = (blockers ?? []).filter { !$0.isEmpty }
        let keepingAwake = names.isEmpty ? "an active sleep assertion" : names.joined(separator: ", ")
        return "\(level): battery at \(alert.batteryPercent)%\(machine). Keeping the Mac awake: \(keepingAwake)."
    }
}
