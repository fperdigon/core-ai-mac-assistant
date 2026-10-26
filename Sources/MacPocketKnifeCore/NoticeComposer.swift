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

public protocol NoticeComposing: Sendable {
    func compose(alert: BatteryAlert, blockers: [String], estimate: BatteryEstimate) -> Notice
    func compose(action: PolicyAction) -> Notice
}

public extension NoticeComposing {
    func compose(alert: BatteryAlert, blockers: [String]) -> Notice {
        compose(alert: alert, blockers: blockers, estimate: BatteryEstimate())
    }
}

public struct NoticeComposer: NoticeComposing {
    public init() {}

    public func compose(
        alert: BatteryAlert, blockers: [String] = [], estimate: BatteryEstimate = BatteryEstimate()
    ) -> Notice {
        let title: String
        switch alert.level {
        case .normal: title = "Battery alert"
        case .urgent: title = "Urgent battery alert"
        case .critical: title = "Critical battery alert"
        }
        let names = SleepBlockerSummary.alertNames(blockers)
        let keepingAwake = names.isEmpty ? "caffeinate or the app's own keep-awake" : names.joined(separator: ", ")
        let remaining = StatusLineFormatter.alertEstimate(estimate)
        return Notice(
            kind: .batteryAlert, title: title,
            body: "Battery at \(alert.batteryPercent)%\(remaining). Keeping the Mac awake: \(keepingAwake).",
            level: alert.level
        )
    }

    /// Compose termination notices only after the corresponding action succeeds.
    public func compose(action: PolicyAction) -> Notice {
        switch action {
        case .notifyDetected(let classified):
            let process = classified.assertion
            let name = SleepBlockerSummary.displayName(for: process.processName) ?? "an active sleep assertion"
            return Notice(
                kind: .keepAwakeDetected, title: "Keep-awake process detected",
                body: "\(name) (PID \(process.pid)) is keeping the Mac awake."
            )
        case .terminate(let pid, let processName, let reason):
            let explanation: String
            switch reason {
            case .consoleStarted: explanation = "started from a console"
            case .batteryThreshold: explanation = "battery threshold reached"
            }
            return Notice(
                kind: .processTerminated, title: "Keep-awake process terminated",
                body: "\(processName) (PID \(pid)) terminated: \(explanation)."
            )
        case .notifyTerminationSkipped(let pid, let reason):
            let explanation: String
            switch reason {
            case .notOwnedByCurrentUser: explanation = "not owned by the current user"
            case .killLoopLimit: explanation = "termination retry limit reached"
            }
            return Notice(
                kind: .terminationSkipped, title: "Termination skipped",
                body: "PID \(pid): \(explanation)."
            )
        case .releaseOwnAssertion:
            return Notice(
                kind: .info, title: "Keep-awake released",
                body: "The app's sleep assertion was released: battery threshold reached."
            )
        }
    }
}
