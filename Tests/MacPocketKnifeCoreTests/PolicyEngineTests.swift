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
import Testing
import MacPocketKnifeCore

private let policyEpoch = Date(timeIntervalSince1970: 1_000)

private func policyAssertion(
    pid: Int32 = 42, name: String = "caffeinate", origin: ProcessOrigin = .app,
    owned: Bool = true, own: Bool = false, type: String = "PreventSystemSleep"
) -> ClassifiedAssertion {
    ClassifiedAssertion(
        assertion: SleepAssertion(pid: pid, processName: name, type: type, name: "Keep awake"),
        origin: origin, isOwnedByCurrentUser: owned, isOwnAppAssertion: own
    )
}

private func policyPower(_ source: PowerSource = .battery, _ percent: Int? = 15) -> PowerState {
    PowerState(source: source, batteryPercent: percent, isCharging: false)
}

private func policyTermination(
    _ classified: ClassifiedAssertion, reason: TerminationReason
) -> PolicyAction {
    .terminate(
        pid: classified.assertion.pid, processName: classified.assertion.processName, reason: reason
    )
}

// Cross every source/level with both origins, ownership states, and blocker kinds.
@Test(arguments: [PowerSource.ac, .battery], [nil, 0, 14, 15, 16, 100] as [Int?])
func policyRuleTable(source: PowerSource, percent: Int?) {
    let lowBattery = source == .battery && percent.map { $0 <= 15 } == true
    for origin in [ProcessOrigin.console, .app] {
        for owned in [false, true] {
            for name in ["caffeinate", "MediaPlayer"] {
                for own in [false, true] {
                    var engine: any PolicyEvaluating = PolicyEngine()
                    let assertion = policyAssertion(name: name, origin: origin, owned: owned, own: own)
                    var expected: [PolicyAction] = []
                    if own {
                        if lowBattery { expected = [.releaseOwnAssertion] }
                    } else if name != "caffeinate" {
                        expected = []
                    } else {
                        expected = [.notifyDetected(assertion)]
                        if origin == .console || lowBattery {
                            expected.append(owned
                                ? policyTermination(assertion, reason: origin == .console
                                    ? .consoleStarted : .batteryThreshold)
                                : .notifyTerminationSkipped(pid: 42, reason: .notOwnedByCurrentUser))
                        }
                    }
                    #expect(engine.evaluate(
                        power: policyPower(source, percent), assertions: [assertion], now: policyEpoch
                    ) == expected)
                }
            }
        }
    }
}

@Test func policyNotificationsAreOncePerPIDUntilDisappearance() {
    let name = "caffeinate"
    var engine = PolicyEngine()
    let first = policyAssertion(name: name)
    let second = policyAssertion(pid: 43, name: name)
    let changed = policyAssertion(name: name, type: "PreventUserIdleSystemSleep")
    let notification: (ClassifiedAssertion) -> PolicyAction = { .notifyDetected($0) }
    let steps: [([ClassifiedAssertion], [PolicyAction])] = [
        ([first, changed], [notification(first)]),
        ([changed], []),
        ([first, second], [notification(second)]),
        ([second], []),
        ([first, second], [notification(first)]),
        ([], []),
        ([first, second], [notification(first), notification(second)]),
    ]
    for (index, step) in steps.enumerated() {
        #expect(engine.evaluate(
            power: policyPower(.ac), assertions: step.0,
            now: policyEpoch.addingTimeInterval(Double(index))
        ) == step.1)
    }
}

@Test func policyDetectionIsNotRepeatedWhenBatteryRuleBecomesEligible() {
    var engine = PolicyEngine()
    let app = policyAssertion()
    let own = policyAssertion(pid: 43, name: "ExampleApp", own: true)
    let other = policyAssertion(pid: 44, name: "MediaPlayer")
    let steps: [(PowerState, [PolicyAction])] = [
        (policyPower(.ac), [.notifyDetected(app)]),
        (policyPower(.battery, 16), []),
        (policyPower(), [policyTermination(app, reason: .batteryThreshold), .releaseOwnAssertion]),
        (policyPower(.ac), []),
        (policyPower(.battery, nil), []),
    ]
    for (index, step) in steps.enumerated() {
        #expect(engine.evaluate(
            power: step.0, assertions: [app, own, other],
            now: policyEpoch.addingTimeInterval(Double(index))
        ) == step.1)
    }
}

@Test(arguments: [ProcessOrigin.console, .app])
func policyMultipleAssertionsIssueOneProcessActionPerEvaluation(origin: ProcessOrigin) {
    var engine = PolicyEngine()
    let first = policyAssertion(origin: origin)
    let second = policyAssertion(origin: origin, type: "PreventUserIdleSystemSleep")
    let termination = policyTermination(
        first, reason: origin == .console ? .consoleStarted : .batteryThreshold
    )
    #expect(engine.evaluate(
        power: policyPower(), assertions: [first, second, first], now: policyEpoch
    ) == [.notifyDetected(first), termination])
    #expect(engine.evaluate(
        power: policyPower(), assertions: [second, first], now: policyEpoch
    ) == [termination])
}

@Test func policyDuplicateOwnAssertionsReleaseOnlyOncePerEvaluation() {
    var engine = PolicyEngine()
    let own = policyAssertion(name: "ExampleApp", own: true)
    #expect(engine.evaluate(
        power: policyPower(), assertions: [own, own], now: policyEpoch
    ) == [.releaseOwnAssertion])
}

@Test(arguments: [ProcessOrigin.console, .app])
func policyKillLoopCountsIssuedActionsAcrossPIDsAndResetsAtWindowBoundary(origin: ProcessOrigin) {
    var engine = PolicyEngine()
    let reason: TerminationReason = origin == .console ? .consoleStarted : .batteryThreshold
    // Three actions are allowed; the fourth and later attempts skip.
    for index in 0..<6 {
        let assertion = policyAssertion(pid: Int32(42 + index), origin: origin)
        let expected: PolicyAction = index < 3
            ? policyTermination(assertion, reason: reason)
            : .notifyTerminationSkipped(pid: assertion.assertion.pid, reason: .killLoopLimit)
        #expect(engine.evaluate(
            power: policyPower(), assertions: [assertion], now: policyEpoch
        ) == [.notifyDetected(assertion), expected])
    }
    let assertion = policyAssertion(pid: 48, origin: origin)
    #expect(engine.evaluate(power: policyPower(), assertions: [], now: policyEpoch) == [])
    #expect(engine.evaluate(
        power: policyPower(), assertions: [assertion], now: policyEpoch.addingTimeInterval(59)
    ) == [.notifyDetected(assertion), .notifyTerminationSkipped(pid: 48, reason: .killLoopLimit)])
    #expect(engine.evaluate(
        power: policyPower(), assertions: [assertion], now: policyEpoch.addingTimeInterval(60)
    ) == [policyTermination(assertion, reason: reason)])
}

@Test func policyKillLoopCountsActionsWithinOneEvaluation() {
    var engine = PolicyEngine(settings: PolicySettings(maxKillsPerWindow: 1))
    let assertions = (42...44).map { policyAssertion(pid: Int32($0), origin: .console) }
    #expect(engine.evaluate(power: policyPower(.ac), assertions: assertions, now: policyEpoch) == [
        .notifyDetected(assertions[0]), policyTermination(assertions[0], reason: .consoleStarted),
        .notifyDetected(assertions[1]), .notifyTerminationSkipped(pid: 43, reason: .killLoopLimit),
        .notifyDetected(assertions[2]), .notifyTerminationSkipped(pid: 44, reason: .killLoopLimit),
    ])
}

@Test func policyKillLoopUsesRollingWindowAndCountsBothTerminationReasons() {
    var engine = PolicyEngine(settings: PolicySettings(maxKillsPerWindow: 1, killWindow: 10))
    let console = policyAssertion(origin: .console)
    let app = policyAssertion(pid: 43)
    let steps: [(TimeInterval, ClassifiedAssertion, [PolicyAction])] = [
        (0, console, [.notifyDetected(console), policyTermination(console, reason: .consoleStarted)]),
        (5, app, [.notifyDetected(app), .notifyTerminationSkipped(pid: 43, reason: .killLoopLimit)]),
        (9, app, [.notifyTerminationSkipped(pid: 43, reason: .killLoopLimit)]),
        (10, app, [policyTermination(app, reason: .batteryThreshold)]),
        (14, app, [.notifyTerminationSkipped(pid: 43, reason: .killLoopLimit)]),
        (15, app, [.notifyTerminationSkipped(pid: 43, reason: .killLoopLimit)]),
    ]
    for step in steps {
        #expect(engine.evaluate(
            power: policyPower(), assertions: [step.1], now: policyEpoch.addingTimeInterval(step.0)
        ) == step.2)
    }
}

@Test func policyNotOwnedSkipsDoNotConsumeKillBudget() {
    var engine = PolicyEngine(settings: PolicySettings(maxKillsPerWindow: 0))
    let foreign = policyAssertion(origin: .console, owned: false)
    for index in 0..<5 {
        let expected: [PolicyAction] = (index == 0 ? [.notifyDetected(foreign)] : [])
            + [.notifyTerminationSkipped(pid: 42, reason: .notOwnedByCurrentUser)]
        #expect(engine.evaluate(
            power: policyPower(), assertions: [foreign], now: policyEpoch
        ) == expected)
    }
    let owned = policyAssertion(origin: .console)
    #expect(engine.evaluate(power: policyPower(), assertions: [owned], now: policyEpoch) == [
        .notifyTerminationSkipped(pid: 42, reason: .killLoopLimit),
    ])
    #expect(engine.evaluate(power: policyPower(), assertions: [foreign], now: policyEpoch) == [
        .notifyTerminationSkipped(pid: 42, reason: .notOwnedByCurrentUser),
    ])
}

@Test func policyCustomBatteryThresholdIsInclusive() {
    var engine = PolicyEngine(settings: PolicySettings(killThresholdPercent: 30))
    let app = policyAssertion()
    let own = policyAssertion(pid: 43, name: "ExampleApp", own: true)
    #expect(engine.evaluate(
        power: policyPower(.battery, 31), assertions: [app, own], now: policyEpoch
    ) == [.notifyDetected(app)])
    #expect(engine.evaluate(
        power: policyPower(.battery, 30), assertions: [app, own], now: policyEpoch
    ) == [policyTermination(app, reason: .batteryThreshold), .releaseOwnAssertion])
}

@Test func policySettingsMatchDefaults() {
    let settings = PolicySettings()
    #expect(settings.killThresholdPercent == 15)
    #expect(settings.maxKillsPerWindow == 3)
    #expect(settings.killWindow == 60)
    #expect(settings == PolicySettings())
}

@Test(arguments: [
    (-1, -1, -1.0, 0, 0, 1.0),
    (101, 5, 0.5, 100, 5, 1.0),
    (30, 2, 12.5, 30, 2, 12.5),
    (15, 3, Double.nan, 15, 3, 60.0),
    (15, 3, Double.infinity, 15, 3, 60.0),
])
func policySettingsNormalizeInvalidValues(
    threshold: Int, count: Int, window: TimeInterval,
    expectedThreshold: Int, expectedCount: Int, expectedWindow: TimeInterval
) {
    let settings = PolicySettings(
        killThresholdPercent: threshold, maxKillsPerWindow: count, killWindow: window
    )
    #expect(settings.killThresholdPercent == expectedThreshold)
    #expect(settings.maxKillsPerWindow == expectedCount)
    #expect(settings.killWindow == expectedWindow)
}
