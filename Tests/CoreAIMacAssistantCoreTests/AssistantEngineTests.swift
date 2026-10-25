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
import Testing
import CoreAIMacAssistantCore

private final class EngineAssertions: AssertionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SleepAssertion] = []

    func set(_ assertions: [SleepAssertion]) { lock.withLock { values = assertions } }
    func currentAssertions() -> [SleepAssertion] { lock.withLock { values } }
    func remove(_ pid: Int32) { lock.withLock { values.removeAll { $0.pid == pid } } }
}

@MainActor
private final class EngineSettings: AssistantSettingsProviding {
    var settings = AppSettings()
}

@MainActor
private final class EngineClock: AssistantClock {
    var now = Date(timeIntervalSince1970: 0)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@MainActor
private final class EngineTicks: AssistantTickScheduling {
    var action: (@MainActor @Sendable () async -> Void)?
    var interval: TimeInterval?
    private let cancellation = EngineCancellation()

    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> @Sendable () -> Void {
        self.interval = interval
        self.action = action
        let cancellation = self.cancellation
        return { cancellation.cancel() }
    }

    func fire() async {
        if !cancellation.isCancelled { await action?() }
    }
}

private final class EngineCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

@MainActor
private final class EngineNotices: AlertNotifying {
    var notices: [Notice] = []
    func deliver(_ notice: Notice) async { notices.append(notice) }
}

@MainActor
private final class EngineTerminator: ProcessTerminating {
    var calls: [Int32] = []
    var result: ProcessTerminationResult = .terminated
    let assertions: EngineAssertions

    init(_ assertions: EngineAssertions) { self.assertions = assertions }

    func terminate(pid: Int32, expectedName: String) async -> ProcessTerminationResult {
        calls.append(pid)
        if result != .failed { assertions.remove(pid) }
        return result
    }
}

private func enginePower(_ source: PowerSource = .battery, _ percent: Int? = 80) -> PowerState {
    PowerState(source: source, batteryPercent: percent, isCharging: source == .ac)
}

private func engineAssertion(pid: Int32 = 42, name: String = "caffeinate") -> SleepAssertion {
    SleepAssertion(pid: pid, processName: name, type: "PreventSystemSleep", name: "Keep awake")
}

@MainActor
private struct EngineFixture {
    let power: FakePowerMonitor
    let assertions = EngineAssertions()
    let settings = EngineSettings()
    let clock = EngineClock()
    let ticks = EngineTicks()
    let notices = EngineNotices()
    let holder = FakeSleepAssertionHolder()
    let controller: CaffeinateController
    let terminator: EngineTerminator
    let engine: AssistantEngine

    init(source: PowerSource = .battery, percent: Int? = 80, console: Bool = false, userID: UInt32? = 42,
         policy: any PolicyEvaluating = PolicyEngine()) {
        power = FakePowerMonitor(current: enginePower(source, percent))
        controller = CaffeinateController(holder: holder, scheduler: FakeKeepAwakeScheduler(),
                                          store: FakeKeepAwakeStateStore())
        terminator = EngineTerminator(assertions)
        let table = FakeProcessTable([
            ProcessSnapshot(pid: 42, parentPID: 41, name: "caffeinate",
                            hasControllingTerminal: console, userID: userID),
            ProcessSnapshot(pid: 41, parentPID: 1, name: console ? "zsh" : "ExampleApp",
                            hasControllingTerminal: console, userID: userID),
        ])
        engine = AssistantEngine(
            powerMonitor: power, assertionProvider: assertions,
            classifier: ProcessClassifier(processTable: table), policyEngine: policy,
            caffeinateController: controller,
            channels: [notices], terminator: terminator, settings: settings,
            clock: clock, tickScheduler: ticks, ownPID: 99, currentUserID: 42,
            batteryEstimator: EmptyBatteryEstimator()
        )
    }
}

@Test(arguments: [PowerSource.ac, .battery])
@MainActor func engineTerminatesConsoleImmediately(source: PowerSource) async {
    let fixture = EngineFixture(source: source, console: true)
    fixture.assertions.set([engineAssertion(), engineAssertion()])
    await fixture.engine.start()
    #expect(fixture.terminator.calls == [42])
    #expect(fixture.notices.notices.filter { $0.kind == .processTerminated }.count == 1)
    #expect(fixture.engine.blockers.isEmpty)
    #expect(fixture.ticks.interval == 10)
    await fixture.ticks.fire()
    #expect(fixture.terminator.calls == [42])
    fixture.engine.stop()
}

@Test @MainActor func engineReportsAppOnceAndTerminatesOnlyAtBatteryThreshold() async {
    let fixture = EngineFixture(source: .ac, percent: 10)
    fixture.assertions.set([engineAssertion()])
    await fixture.engine.start()
    await fixture.ticks.fire()
    #expect(fixture.terminator.calls.isEmpty)
    fixture.power.push(enginePower(.battery, 16))
    await fixture.engine.evaluate()
    #expect(fixture.terminator.calls.isEmpty)
    fixture.power.push(enginePower(.battery, 15))
    await fixture.engine.evaluate()
    #expect(fixture.terminator.calls == [42])
    #expect(fixture.notices.notices.filter { $0.kind == .keepAwakeDetected }.count == 1)
    fixture.engine.stop()
}

@Test @MainActor func engineReleasesOwnAssertionEvenBeforeProviderReportsIt() async {
    let fixture = EngineFixture(percent: 16)
    fixture.controller.activate()
    await fixture.engine.start()
    #expect(fixture.controller.isActive)
    #expect(fixture.engine.blockers.isEmpty)
    #expect(fixture.engine.blockersText == nil)
    fixture.power.push(enginePower(.battery, 15))
    await fixture.engine.evaluate()
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles.count == 1)
    #expect(fixture.terminator.calls.isEmpty)
    #expect(fixture.engine.blockers.isEmpty)
    fixture.engine.stop()
}

@Test(arguments: [UInt32(43), nil] as [UInt32?])
@MainActor func engineNeverTerminatesForeignOrUnknownOwner(userID: UInt32?) async {
    let fixture = EngineFixture(percent: 10, console: true, userID: userID)
    fixture.assertions.set([engineAssertion()])
    await fixture.engine.start()
    #expect(fixture.terminator.calls.isEmpty)
    #expect(fixture.notices.notices.contains { $0.kind == .terminationSkipped })
    fixture.engine.stop()
}

@Test @MainActor func engineClockDrivesCadenceAndSettingsApplyOnNextTick() async {
    let fixture = EngineFixture()
    fixture.assertions.set([engineAssertion()])
    await fixture.engine.start()
    func batteryCount() -> Int { fixture.notices.notices.filter { $0.kind == .batteryAlert }.count }
    #expect(batteryCount() == 1)
    fixture.clock.advance(599)
    await fixture.ticks.fire()
    #expect(batteryCount() == 1)
    fixture.clock.advance(1)
    await fixture.ticks.fire()
    #expect(batteryCount() == 2)
    fixture.settings.settings.alerts = AlertSettings(normalInterval: 10)
    fixture.clock.advance(10)
    await fixture.ticks.fire()
    #expect(batteryCount() == 3)
    fixture.power.push(enginePower(.battery, 25))
    await fixture.engine.evaluate()
    #expect(fixture.terminator.calls.isEmpty)
    fixture.settings.settings.policy = PolicySettings(killThresholdPercent: 30)
    await fixture.ticks.fire()
    #expect(fixture.terminator.calls == [42])
    // Runtime policy configuration must not reset detection history.
    #expect(fixture.notices.notices.filter { $0.kind == .keepAwakeDetected }.count == 1)
    fixture.engine.stop()
    fixture.clock.advance(1000)
    let count = fixture.notices.notices.count
    await fixture.ticks.fire()
    #expect(fixture.notices.notices.count == count)
}

@Test @MainActor func engineFailureOutcomeDoesNotClaimSuccessAndOtherBlockersRemain() async {
    let fixture = EngineFixture(percent: 10)
    fixture.terminator.result = .failed
    fixture.assertions.set([engineAssertion(), engineAssertion(pid: 44, name: "MediaPlayer")])
    await fixture.engine.start()
    #expect(fixture.terminator.calls == [42])
    #expect(!fixture.notices.notices.contains { $0.kind == .processTerminated })
    #expect(fixture.notices.notices.contains { $0.title == "Termination failed" })
    #expect(fixture.engine.blockers == ["MediaPlayer", "caffeinate"])
    fixture.engine.stop()
}

@Test @MainActor func engineEmptyProvidersAndUnknownPowerAreSafe() async {
    let fixture = EngineFixture(percent: nil)
    await fixture.engine.start()
    await fixture.engine.start()
    await fixture.ticks.fire()
    #expect(fixture.notices.notices.isEmpty)
    #expect(fixture.terminator.calls.isEmpty)
    #expect(fixture.engine.statusText.contains("Battery unknown"))
    fixture.engine.stop()
    fixture.engine.stop()
}

@Test @MainActor func enginePowerChangeTriggersEvaluationWithoutTick() async {
    let fixture = EngineFixture(source: .ac)
    fixture.assertions.set([engineAssertion()])
    await fixture.engine.start()
    await withCheckedContinuation { continuation in
        fixture.engine.onChange = { continuation.resume() }
        fixture.power.push(enginePower(.battery, 15))
    }
    fixture.engine.onChange = nil
    #expect(fixture.terminator.calls == [42])
    fixture.engine.stop()
}

@Test @MainActor func engineAlertsStopOnACOrWhenBlockersDisappear() async {
    let fixture = EngineFixture()
    fixture.assertions.set([engineAssertion(pid: 44, name: "MediaPlayer")])
    await fixture.engine.start()
    func batteryCount() -> Int { fixture.notices.notices.filter { $0.kind == .batteryAlert }.count }
    #expect(batteryCount() == 1)
    fixture.power.push(enginePower(.ac))
    await fixture.engine.evaluate()
    fixture.clock.advance(1000)
    await fixture.ticks.fire()
    #expect(batteryCount() == 1)
    fixture.power.push(enginePower())
    await fixture.engine.evaluate()
    #expect(batteryCount() == 2)
    fixture.assertions.set([])
    await fixture.ticks.fire()
    fixture.clock.advance(1000)
    await fixture.ticks.fire()
    #expect(batteryCount() == 2)
    fixture.assertions.set([engineAssertion(pid: 44, name: "MediaPlayer")])
    await fixture.ticks.fire()
    #expect(batteryCount() == 3)
    #expect(fixture.terminator.calls.isEmpty)
    fixture.engine.stop()
}

@Test @MainActor func engineSettingsChangesPreserveTerminationRetryHistory() async {
    let fixture = EngineFixture(console: true)
    fixture.terminator.result = .failed
    fixture.assertions.set([engineAssertion()])
    await fixture.engine.start()
    fixture.settings.settings.policy = PolicySettings(killThresholdPercent: 20)
    await fixture.ticks.fire()
    fixture.settings.settings.policy = PolicySettings(killThresholdPercent: 25)
    await fixture.ticks.fire()
    fixture.settings.settings.policy = PolicySettings(killThresholdPercent: 30)
    await fixture.ticks.fire()
    #expect(fixture.terminator.calls == [42, 42, 42])
    #expect(fixture.notices.notices.contains { $0.body.contains("retry limit") })
    #expect(fixture.notices.notices.filter { $0.kind == .keepAwakeDetected }.count == 1)
    fixture.clock.advance(60)
    await fixture.ticks.fire()
    #expect(fixture.terminator.calls == [42, 42, 42, 42])
    fixture.engine.stop()
}

private struct EmptyBatteryEstimator: BatteryEstimating {
    func currentEstimate() -> BatteryEstimate { BatteryEstimate() }
}

private final class RecordingDisplayPolicy: PolicyEvaluating, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ClassifiedAssertion] = []
    var assertions: [ClassifiedAssertion] { lock.withLock { values } }
    func evaluate(power: PowerState, assertions: [ClassifiedAssertion], now: Date) -> [PolicyAction] {
        lock.withLock { values = assertions }
        return []
    }
}

@Test @MainActor func engineCleansDisplayAndAlertsButPolicyReceivesEveryAssertion() async {
    let policy = RecordingDisplayPolicy()
    let fixture = EngineFixture(policy: policy)
    let assertions = [
        engineAssertion(pid: 99, name: AppInfo.name),
        engineAssertion(pid: 2, name: "powerd"),
        engineAssertion(pid: 3, name: "coreaudiod"),
        engineAssertion(pid: 4, name: "Claude"),
    ]
    fixture.assertions.set(assertions)
    fixture.engine.refreshStatusSnapshot()
    #expect(fixture.engine.blockersText == "Also keeping awake: Claude, audio playback")
    await fixture.engine.start()
    #expect(policy.assertions.map(\.assertion) == assertions)
    #expect(fixture.engine.blockers == ["Claude", "audio playback"])
    let alert = fixture.notices.notices.first { $0.kind == .batteryAlert }
    #expect(alert?.body == "Battery at 80%. Keeping the Mac awake: Claude, audio playback.")
    fixture.assertions.set(Array(assertions.prefix(2)))
    fixture.clock.advance(600)
    await fixture.ticks.fire()
    #expect(fixture.engine.blockersText == nil)
    #expect(policy.assertions.count == 2)
    // Alert eligibility still uses raw assertions, even when all display names are hidden.
    #expect(fixture.notices.notices.filter { $0.kind == .batteryAlert }.count == 2)
    fixture.engine.stop()
}

@Test @MainActor func engineDetectionMessagesHideInternalsAndMapAudioPlayback() async {
    let fixture = EngineFixture()
    fixture.assertions.set([
        engineAssertion(pid: 99, name: AppInfo.name),
        engineAssertion(pid: 2, name: "powerd"),
        engineAssertion(pid: 3, name: "coreaudiod"),
    ])
    await fixture.engine.start()
    let detections = fixture.notices.notices.filter { $0.kind == .keepAwakeDetected }
    #expect(detections.count == 1)
    #expect(detections.first?.body == "audio playback (PID 3) is keeping the Mac awake. Report only.")
    fixture.engine.stop()
}
