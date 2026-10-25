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

public struct AlertScheduler: AlertScheduling {
    public var settings: AlertSettings

    private var previousLevel: AlertLevel?
    private var lastAlertTime: Date?

    public init(settings: AlertSettings = AlertSettings()) {
        self.settings = settings
    }

    /// Ineligible evaluations reset the session, including an unknown battery level.
    /// Level changes never restart the interval unless an alert is emitted.
    public mutating func evaluate(
        power: PowerState, blockerActive: Bool, now: Date
    ) -> BatteryAlert? {
        guard power.source == .battery, blockerActive,
              let percent = power.batteryPercent else {
            previousLevel = nil
            lastAlertTime = nil
            return nil
        }

        let level: AlertLevel
        let interval: TimeInterval
        if percent < settings.criticalBelowPercent {
            level = .critical
            interval = settings.criticalInterval
        } else if percent < settings.urgentBelowPercent {
            level = .urgent
            interval = settings.urgentInterval
        } else {
            level = .normal
            interval = settings.normalInterval
        }

        let escalated = previousLevel.map { level > $0 } ?? false
        previousLevel = level
        if let lastAlertTime, !escalated,
           now.timeIntervalSince(lastAlertTime) < interval {
            return nil
        }

        lastAlertTime = now
        return BatteryAlert(level: level, batteryPercent: percent)
    }
}
