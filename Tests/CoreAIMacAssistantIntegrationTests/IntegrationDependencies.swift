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
import CoreAIMacAssistantCore

@MainActor
final class IntegrationPower: PowerMonitoring {
    var current: PowerState

    init(source: PowerSource = .battery, percent: Int = 16) {
        current = PowerState(source: source, batteryPercent: percent, isCharging: source == .ac)
    }

    func start(_ handler: @escaping @Sendable (PowerState) -> Void) {}
    func stop() {}
}

@MainActor
final class IntegrationTime: AssistantClock, AssistantTickScheduling, KeepAwakeScheduling {
    var now = Date(timeIntervalSince1970: 1_000)
    private var tick: (@MainActor @Sendable () async -> Void)?

    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> @Sendable () -> Void {
        tick = action
        return {}
    }

    func schedule(
        at date: Date, action: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void {
        // Integration scenarios activate indefinite assertions only.
        preconditionFailure("Unexpected expiry in integration test")
    }

    func fire() async {
        now.addTimeInterval(10)
        await tick?()
    }
}

@MainActor
final class IntegrationStore: KeepAwakeStateStore {
    var state: KeepAwakeState?
    func load() -> KeepAwakeState? { state }
    func save(_ state: KeepAwakeState?) { self.state = state }
}

@MainActor
final class IntegrationSettings: AssistantSettingsProviding {
    let settings = AppSettings()
}

@MainActor
final class IntegrationNotices: AlertNotifying {
    var notices: [Notice] = []
    func deliver(_ notice: Notice) async { notices.append(notice) }

    func contains(_ kind: NoticeKind, pid: Int32) -> Bool {
        notices.contains { $0.kind == kind && $0.body.contains("PID \(pid)") }
    }
}

@MainActor
struct IntegrationFixture {
    let power: IntegrationPower
    let time = IntegrationTime()
    let notices = IntegrationNotices()
    let controller: CaffeinateController
    let engine: AssistantEngine

    init(assertions: OwnedAssertions, process: RealProcess? = nil,
         source: PowerSource = .battery, percent: Int = 16) {
        power = IntegrationPower(source: source, percent: percent)
        controller = CaffeinateController(
            holder: IOKitSleepAssertionHolder(), scheduler: time, store: IntegrationStore()
        )
        engine = AssistantEngine(
            powerMonitor: power, assertionProvider: assertions,
            classifier: ProcessClassifier(processTable: SysctlProcessTable()),
            caffeinateController: controller, channels: [notices],
            terminator: SignalProcessTerminator(waiter: ProcessExitWaiter(process: process)),
            settings: IntegrationSettings(), clock: time, tickScheduler: time,
            batteryEstimator: EmptyBatteryEstimator()
        )
    }

    func stop() {
        engine.stop()
        controller.deactivate()
    }
}

private struct EmptyBatteryEstimator: BatteryEstimating {
    func currentEstimate() -> BatteryEstimate { BatteryEstimate() }
}
