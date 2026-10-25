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

private struct AlertStep: Sendable {
    let seconds: TimeInterval
    let percent: Int?
    var source: PowerSource = .battery
    var blockerActive: Bool = true
    let expected: AlertLevel?
}

private func checkAlertSteps(
    _ steps: [AlertStep], settings: AlertSettings = AlertSettings()
) {
    var scheduler: any AlertScheduling = AlertScheduler(settings: settings)
    for step in steps {
        let power = PowerState(
            source: step.source, batteryPercent: step.percent, isCharging: false
        )
        let alert = scheduler.evaluate(
            power: power, blockerActive: step.blockerActive,
            now: Date(timeIntervalSince1970: step.seconds)
        )
        let expected = step.expected.flatMap { level in
            step.percent.map { BatteryAlert(level: level, batteryPercent: $0) }
        }
        #expect(alert == expected)
    }
}

@Test(arguments: [
    (100, AlertLevel.normal, 600.0),
    (50, AlertLevel.normal, 600.0),
    (49, AlertLevel.urgent, 120.0),
    (20, AlertLevel.urgent, 120.0),
    (19, AlertLevel.critical, 60.0),
    (0, AlertLevel.critical, 60.0),
])
func alertsImmediatelyAndRepeatsAtCurrentInterval(
    percent: Int, level: AlertLevel, interval: TimeInterval
) {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: percent, expected: level),
        AlertStep(seconds: 0, percent: percent, expected: nil),
        AlertStep(seconds: interval - 1, percent: percent, expected: nil),
        AlertStep(seconds: interval, percent: percent, expected: level),
        AlertStep(seconds: interval * 2 - 1, percent: percent, expected: nil),
        AlertStep(seconds: interval * 2 + 1, percent: percent, expected: level),
    ])
}

@Test func escalationAlertsImmediatelyAndRestartsInterval() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 80, expected: .normal),
        AlertStep(seconds: 1, percent: 49, expected: .urgent),
        AlertStep(seconds: 2, percent: 19, expected: .critical),
        AlertStep(seconds: 61, percent: 18, expected: nil),
        AlertStep(seconds: 62, percent: 17, expected: .critical),
    ])
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 80, expected: .normal),
        AlertStep(seconds: 1, percent: 10, expected: .critical),
    ])
}

@Test func deescalationUsesCurrentIntervalSinceLastAlert() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 19, expected: .critical),
        AlertStep(seconds: 10, percent: 20, expected: nil),
        AlertStep(seconds: 119, percent: 21, expected: nil),
        AlertStep(seconds: 120, percent: 22, expected: .urgent),
        AlertStep(seconds: 121, percent: 50, expected: nil),
        AlertStep(seconds: 719, percent: 51, expected: nil),
        AlertStep(seconds: 720, percent: 52, expected: .normal),
    ])
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 19, expected: .critical),
        AlertStep(seconds: 200, percent: 30, expected: .urgent),
    ])
}

@Test func escalationAfterUnalertedDeescalationIsImmediate() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 19, expected: .critical),
        AlertStep(seconds: 1, percent: 20, expected: nil),
        AlertStep(seconds: 2, percent: 19, expected: .critical),
        AlertStep(seconds: 61, percent: 18, expected: nil),
        AlertStep(seconds: 62, percent: 18, expected: .critical),
    ])
}

@Test func acPowerResetsAlerts() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 19, source: .ac, expected: nil),
        AlertStep(seconds: 1, percent: 19, expected: .critical),
        AlertStep(seconds: 2, percent: 19, source: .ac, expected: nil),
        AlertStep(seconds: 3, percent: 80, expected: .normal),
    ])
}

@Test func missingBlockerResetsAlerts() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 19, blockerActive: false, expected: nil),
        AlertStep(seconds: 1, percent: 19, expected: .critical),
        AlertStep(seconds: 2, percent: 19, blockerActive: false, expected: nil),
        AlertStep(seconds: 3, percent: 80, expected: .normal),
    ])
}

@Test func unknownBatteryPercentSuppressesAndResetsAlerts() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: nil, expected: nil),
        AlertStep(seconds: 1, percent: 80, expected: .normal),
        AlertStep(seconds: 2, percent: nil, expected: nil),
        AlertStep(seconds: 3, percent: 80, expected: .normal),
    ])
}

@Test func earlierTimeDoesNotRepeatOrMoveLastAlertTime() {
    checkAlertSteps([
        AlertStep(seconds: 100, percent: 19, expected: .critical),
        AlertStep(seconds: 90, percent: 19, expected: nil),
        AlertStep(seconds: 159, percent: 19, expected: nil),
        AlertStep(seconds: 160, percent: 19, expected: .critical),
    ])
}

@Test func customAlertSettingsControlThresholdsAndIntervals() {
    checkAlertSteps([
        AlertStep(seconds: 0, percent: 70, expected: .normal),
        AlertStep(seconds: 9, percent: 70, expected: nil),
        AlertStep(seconds: 10, percent: 70, expected: .normal),
        AlertStep(seconds: 11, percent: 69, expected: .urgent),
        AlertStep(seconds: 14, percent: 30, expected: nil),
        AlertStep(seconds: 15, percent: 30, expected: .urgent),
        AlertStep(seconds: 16, percent: 29, expected: .critical),
        AlertStep(seconds: 17, percent: 29, expected: nil),
        AlertStep(seconds: 18, percent: 29, expected: .critical),
    ], settings: AlertSettings(
        urgentBelowPercent: 70, criticalBelowPercent: 30,
        normalInterval: 10, urgentInterval: 4, criticalInterval: 2
    ))
}

@Test func alertSettingsMatchPlanDefaults() {
    let settings = AlertSettings()
    #expect(settings.urgentBelowPercent == 50)
    #expect(settings.criticalBelowPercent == 20)
    #expect(settings.normalInterval == 600)
    #expect(settings.urgentInterval == 120)
    #expect(settings.criticalInterval == 60)
    #expect(settings == AlertSettings())
}

@Test(arguments: [
    (-10, -20, 1, 0),
    (150, 120, 100, 99),
    (30, 50, 30, 29),
    (20, 20, 20, 19),
    (50, -1, 50, 0),
    (Int.min, Int.max, 1, 0),
])
func alertSettingsClampThresholds(urgent: Int, critical: Int, expectedUrgent: Int, expectedCritical: Int) {
    let settings = AlertSettings(urgentBelowPercent: urgent, criticalBelowPercent: critical)
    #expect(settings.urgentBelowPercent == expectedUrgent)
    #expect(settings.criticalBelowPercent == expectedCritical)
}

@Test(arguments: [-100.0, 0, 0.5, 1, 12.5, Double.nan, Double.infinity, -Double.infinity])
func alertSettingsKeepIntervalsFiniteAndPositive(interval: TimeInterval) {
    let settings = AlertSettings(
        normalInterval: interval, urgentInterval: interval, criticalInterval: interval
    )
    #expect(settings.normalInterval == (interval.isFinite ? max(1, interval) : 600))
    #expect(settings.urgentInterval == (interval.isFinite ? max(1, interval) : 120))
    #expect(settings.criticalInterval == (interval.isFinite ? max(1, interval) : 60))
}

@Test func alertLevelsCompareInSeverityOrder() {
    let levels: [AlertLevel] = [.normal, .urgent, .critical]
    for (leftIndex, left) in levels.enumerated() {
        for (rightIndex, right) in levels.enumerated() {
            #expect((left < right) == (leftIndex < rightIndex))
            #expect((left == right) == (leftIndex == rightIndex))
        }
    }
}
