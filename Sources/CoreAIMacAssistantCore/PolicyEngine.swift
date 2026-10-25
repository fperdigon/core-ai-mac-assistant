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

public struct PolicyEngine: PolicyEvaluating {
    public var settings: PolicySettings

    private var seenPIDs: Set<Int32> = []
    private var terminations: [Termination] = []

    private struct Termination: Sendable {
        let processName: String
        let date: Date
    }

    public init(settings: PolicySettings = PolicySettings()) {
        self.settings = settings
    }

    /// Notifications are emitted once per PID until it disappears. Actions follow
    /// input order, with detection preceding termination or its skip notice.
    /// Termination history uses the half-open window (now - killWindow, now].
    public mutating func evaluate(
        power: PowerState, assertions: [ClassifiedAssertion], now: Date
    ) -> [PolicyAction] {
        seenPIDs.formIntersection(Set(assertions.map { $0.assertion.pid }))
        terminations.removeAll { now.timeIntervalSince($0.date) >= settings.killWindow }
        let batteryThresholdReached = power.source == .battery
            && power.batteryPercent.map { $0 <= settings.killThresholdPercent } == true
        var actions: [PolicyAction] = []
        var attemptedPIDs: Set<Int32> = []
        var releasedOwnAssertion = false

        for classified in assertions {
            if classified.isOwnAppAssertion {
                if batteryThresholdReached, !releasedOwnAssertion {
                    actions.append(.releaseOwnAssertion)
                    releasedOwnAssertion = true
                }
                continue
            }

            let assertion = classified.assertion
            if seenPIDs.insert(assertion.pid).inserted {
                actions.append(assertion.isCaffeinate
                    ? .notifyDetected(classified) : .notifyReportOnly(classified))
            }
            guard assertion.isCaffeinate else { continue }

            let reason: TerminationReason
            if classified.origin == .console {
                reason = .consoleStarted
            } else if batteryThresholdReached {
                reason = .batteryThreshold
            } else {
                continue
            }
            // A process may hold several assertions, but needs only one action.
            guard attemptedPIDs.insert(assertion.pid).inserted else { continue }
            guard classified.isOwnedByCurrentUser else {
                actions.append(.notifyTerminationSkipped(
                    pid: assertion.pid, reason: .notOwnedByCurrentUser
                ))
                continue
            }
            let recentCount = terminations.filter {
                $0.processName == assertion.processName && $0.date <= now
            }.count
            guard recentCount < settings.maxKillsPerWindow else {
                actions.append(.notifyTerminationSkipped(pid: assertion.pid, reason: .killLoopLimit))
                continue
            }
            actions.append(.terminate(
                pid: assertion.pid, processName: assertion.processName, reason: reason
            ))
            terminations.append(Termination(processName: assertion.processName, date: now))
        }
        return actions
    }
}
