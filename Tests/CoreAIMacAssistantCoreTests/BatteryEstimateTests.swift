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

@Test func batteryEstimateUsesSystemMinutesAndUnsignedCurrent() throws {
    let estimate = BatteryEstimateParser.parse([
        "TimeRemaining": 416, "AvgTimeToEmpty": 400,
        "Amperage": NSNumber(value: UInt64(18_446_744_073_709_550_996)),
        "InstantAmperage": NSNumber(value: UInt64.max), "Voltage": 13_031,
        "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
        "CurrentCapacity": 99, "MaxCapacity": 100,
        "AppleRawCurrentCapacity": 4_000, "AppleRawMaxCapacity": 4_100,
    ])
    #expect(estimate.timeRemaining == 24_960.0)
    let watts = try #require(estimate.powerWatts)
    #expect(abs(watts - 8.07922) < 0.00001)
}

@Test func batteryEstimateChargingUsesTimeToFull() {
    let estimate = BatteryEstimateParser.parse([
        "ExternalConnected": true, "IsCharging": true,
        "TimeRemaining": 416, "AvgTimeToEmpty": 900, "AvgTimeToFull": 128,
        "Amperage": 1_000, "Voltage": 12_000,
    ])
    #expect(estimate == BatteryEstimate(timeRemaining: 128 * 60, powerWatts: 12))
    let plugged = BatteryEstimateParser.parse([
        "ExternalConnected": true, "FullyCharged": true, "TimeRemaining": 416,
    ])
    #expect(plugged.timeRemaining == nil)
}

@Test func batteryEstimatePrefersPowerSourceTimeAndUsesFallbackWhenCalculating() {
    let properties: [String: Any] = [
        "ExternalConnected": false, "IsCharging": false,
        "TimeRemaining": 464, "AvgTimeToEmpty": 450,
    ]
    let smoothed = BatteryEstimateParser.parse(
        properties, powerSourceDescription: ["Time to Empty": 436]
    )
    #expect(smoothed.timeRemaining == Double(436 * 60))

    let calculating = BatteryEstimateParser.parse(
        properties, powerSourceDescription: ["Time to Empty": -1]
    )
    #expect(calculating.timeRemaining == Double(464 * 60))
}

@Test func batteryEstimateChargingUsesPowerSourceTimeToFull() {
    let estimate = BatteryEstimateParser.parse(
        ["ExternalConnected": true, "IsCharging": true, "AvgTimeToFull": 128],
        powerSourceDescription: ["Time to Full Charge": 91]
    )
    #expect(estimate.timeRemaining == Double(91 * 60))
}

@Test(arguments: [0, 65_535, -1])
func batteryEstimateRejectsUnknownMinutes(minutes: Int) {
    let estimate = BatteryEstimateParser.parse([
        "TimeRemaining": minutes, "ExternalConnected": false,
    ])
    #expect(estimate.timeRemaining == nil)
}

@Test func batteryEstimateMissingAndInvalidValuesAreSafe() {
    #expect(BatteryEstimateParser.parse([:]) == BatteryEstimate())
    for current in [0.0, Double.nan, Double.infinity] {
        let estimate = BatteryEstimateParser.parse([
            "Amperage": current, "Voltage": 13_031,
            "AppleRawCurrentCapacity": 4_000, "TimeRemaining": 65_535,
        ])
        #expect(estimate == BatteryEstimate())
    }
    for voltage in [0.0, -1, Double.nan, Double.infinity] {
        #expect(BatteryEstimateParser.parse([
            "Amperage": -620, "Voltage": voltage,
        ]).powerWatts == nil)
    }
}

@Test func batteryEstimateFallsBackToAverageThenRawCapacity() {
    #expect(BatteryEstimateParser.parse([
        "TimeRemaining": 65_535, "AvgTimeToEmpty": 42,
    ]).timeRemaining == 2_520.0)
    #expect(BatteryEstimateParser.parse([
        "TimeRemaining": 65_535, "AvgTimeToEmpty": 0,
        "AppleRawCurrentCapacity": 1_240, "Amperage": -620,
    ]).timeRemaining == 7_200)
    #expect(BatteryEstimateParser.parse([
        "CurrentCapacity": 99, "MaxCapacity": 100, "Amperage": -620,
    ]).timeRemaining == nil)
    #expect(BatteryEstimateParser.parse([
        "AppleRawCurrentCapacity": Double.infinity, "Amperage": -620,
    ]).timeRemaining == nil)
    #expect(BatteryEstimateParser.parse([
        "InstantAmperage": -620, "Voltage": 13_031,
    ]).powerWatts == 8.07922)
    #expect(BatteryEstimateParser.parse([
        "IsCharging": true, "AvgTimeToFull": 65_535, "TimeRemaining": 42,
    ]).timeRemaining == 2_520.0)
}

@Test func statusLineFormatsAllPowerStatesAndPreservesBlockers() {
    let examples: [(PowerState, BatteryEstimate, String)] = [
        (PowerState(source: .battery, batteryPercent: 99, isCharging: false),
         BatteryEstimate(timeRemaining: 416 * 60, powerWatts: 8.07922),
         "Battery 99% · on battery · 6h 56m left · 8.1 W"),
        (PowerState(source: .ac, batteryPercent: 25, isCharging: true),
         BatteryEstimate(timeRemaining: 128 * 60),
         "Battery 25% · charging · 2h 08m to full"),
        (PowerState(source: .ac, batteryPercent: 100, isCharging: false),
         BatteryEstimate(), "Battery 100% · plugged in"),
        (PowerState(source: .battery, batteryPercent: 40, isCharging: false),
         BatteryEstimate(), "Battery 40% · on battery · estimating…"),
        (PowerState(source: .ac, batteryPercent: nil, isCharging: false),
         BatteryEstimate(), "Battery unknown · plugged in"),
    ]
    for (power, estimate, expected) in examples {
        #expect(StatusLineFormatter.format(power: power, estimate: estimate, blockers: [])
            == expected + " · No sleep blockers")
        #expect(StatusLineFormatter.format(power: power, estimate: estimate, blockers: ["MediaPlayer", "caffeinate"])
            == expected + " · Keeping awake: MediaPlayer, caffeinate")
    }
}

@Test(arguments: [
    (0.0, "<1m"), (59, "<1m"), (60, "1m"), (2_520, "42m"),
    (3_599, "59m"), (3_600, "1h 00m"), (4_800, "1h 20m"),
]) func batteryDurationFormatsEdges(seconds: Double, expected: String) {
    #expect(StatusLineFormatter.duration(seconds) == expected)
}

@Test func batteryFormattingRejectsInvalidNumbers() {
    for seconds in [-1.0, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
        #expect(StatusLineFormatter.duration(seconds) == nil)
    }
    #expect(StatusLineFormatter.duration(nil) == nil)
    let line = StatusLineFormatter.format(
        power: PowerState(source: .battery, batteryPercent: 40, isCharging: false),
        estimate: BatteryEstimate(timeRemaining: .nan, powerWatts: .infinity), blockers: []
    )
    #expect(line == "Battery 40% · on battery · estimating… · No sleep blockers")
}

@Test(arguments: [AlertLevel.normal, .urgent, .critical])
func batteryAlertBodiesIncludeOnlyKnownEstimates(level: AlertLevel) {
    let alert = BatteryAlert(level: level, batteryPercent: 25)
    let composer: any NoticeComposing = NoticeComposer()
    let formatter: any TelegramAlertFormatting = TelegramAlertFormatter()
    for seconds: TimeInterval? in [nil, 4_800] {
        let estimate = BatteryEstimate(timeRemaining: seconds)
        let notice = composer.compose(alert: alert, blockers: ["MediaPlayer"], estimate: estimate)
        let telegram = formatter.format(
            alert: alert, blockers: ["MediaPlayer"], includeMachineName: nil, estimate: estimate
        )
        #expect(notice.body.contains("about 1h 20m left") == (seconds != nil))
        #expect(telegram.contains("about 1h 20m left") == (seconds != nil))
        #expect(notice.level == level)
        if seconds == nil {
            #expect(notice == composer.compose(alert: alert, blockers: ["MediaPlayer"]))
            #expect(telegram == formatter.format(alert: alert, blockers: ["MediaPlayer"], includeMachineName: nil))
        }
    }
}

private final class MutableBatteryEstimator: BatteryEstimating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = BatteryEstimate(timeRemaining: 4_800, powerWatts: 8.1)
    func currentEstimate() -> BatteryEstimate { lock.withLock { value } }
    func set(_ estimate: BatteryEstimate) { lock.withLock { value = estimate } }
}

private struct StatusAssertions: AssertionProviding {
    func currentAssertions() -> [SleepAssertion] {
        [SleepAssertion(pid: 42, processName: "MediaPlayer", type: "PreventSystemSleep", name: "Playback")]
    }
}

@MainActor
private final class StatusDependencies: AssistantClock, AssistantTickScheduling, AssistantSettingsProviding,
    AlertNotifying, ProcessTerminating {
    let now = Date(timeIntervalSince1970: 1_000)
    let settings = AppSettings()
    var tick: (@MainActor @Sendable () async -> Void)?
    var notices: [Notice] = []
    func schedule(every interval: TimeInterval,
                  action: @escaping @MainActor @Sendable () async -> Void) -> @Sendable () -> Void {
        tick = action
        return {}
    }
    func deliver(_ notice: Notice) async { notices.append(notice) }
    func terminate(pid: Int32, expectedName: String) async -> ProcessTerminationResult { .failed }
}

@Test @MainActor func engineRefreshesBatteryEstimateOnEveryTick() async {
    let estimator = MutableBatteryEstimator()
    let dependencies = StatusDependencies()
    let power = FakePowerMonitor(current: PowerState(source: .battery, batteryPercent: 40, isCharging: false))
    let controller = CaffeinateController(
        holder: FakeSleepAssertionHolder(), scheduler: FakeKeepAwakeScheduler(), store: FakeKeepAwakeStateStore()
    )
    let engine = AssistantEngine(
        powerMonitor: power, assertionProvider: StatusAssertions(),
        classifier: ProcessClassifier(processTable: FakeProcessTable([])),
        caffeinateController: controller, channels: [dependencies], terminator: dependencies,
        settings: dependencies, clock: dependencies, tickScheduler: dependencies,
        ownPID: 99, currentUserID: 42, batteryEstimator: estimator
    )
    engine.refreshStatusSnapshot()
    #expect(dependencies.notices.isEmpty)
    #expect(engine.statusText == "Battery 40% · on battery · 1h 20m left · 8.1 W · Keeping awake: MediaPlayer")
    await engine.start()
    #expect(dependencies.notices.contains { $0.kind == .batteryAlert && $0.body.contains("about 1h 20m left") })
    estimator.set(BatteryEstimate())
    await dependencies.tick?()
    #expect(engine.statusText == "Battery 40% · on battery · estimating… · Keeping awake: MediaPlayer")
    engine.stop()
}
