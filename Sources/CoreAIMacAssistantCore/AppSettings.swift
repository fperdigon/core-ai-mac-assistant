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

public struct TelegramPreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var chatID: String?
    public var silentMode: Bool
    public var includeMachineName: Bool

    public init(
        isEnabled: Bool = false, chatID: String? = nil,
        silentMode: Bool = false, includeMachineName: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.chatID = chatID
        self.silentMode = silentMode
        self.includeMachineName = includeMachineName
    }
}

/// Non-secret preferences only. Bot credentials belong in SecretStore.
public struct AppSettings: Codable, Equatable, Sendable {
    public var alerts: AlertSettings
    public var policy: PolicySettings
    public var keepAwakeDefaultDuration: TimeInterval?
    public var telegram: TelegramPreferences
    public var launchAtLogin: Bool

    public init(
        alerts: AlertSettings = AlertSettings(), policy: PolicySettings = PolicySettings(),
        keepAwakeDefaultDuration: TimeInterval? = nil,
        telegram: TelegramPreferences = TelegramPreferences(), launchAtLogin: Bool = false
    ) {
        self.alerts = alerts
        self.policy = policy
        self.keepAwakeDefaultDuration = keepAwakeDefaultDuration
        self.telegram = telegram
        self.launchAtLogin = launchAtLogin
    }

    /// Keep thresholds strictly ordered and intervals finite and at least ten seconds.
    public func validated() -> AppSettings {
        var result = self
        let urgent = min(100, max(2, alerts.urgentBelowPercent))
        let critical = min(urgent - 1, max(1, alerts.criticalBelowPercent))
        func interval(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
            value.isFinite ? max(10, value) : fallback
        }
        result.alerts = AlertSettings(
            urgentBelowPercent: urgent, criticalBelowPercent: critical,
            normalInterval: interval(alerts.normalInterval, fallback: 600),
            urgentInterval: interval(alerts.urgentInterval, fallback: 120),
            criticalInterval: interval(alerts.criticalInterval, fallback: 60)
        )
        result.policy = PolicySettings(
            killThresholdPercent: min(50, max(5, policy.killThresholdPercent)),
            maxKillsPerWindow: policy.maxKillsPerWindow,
            killWindow: interval(policy.killWindow, fallback: 60)
        )
        if let duration = keepAwakeDefaultDuration {
            result.keepAwakeDefaultDuration = duration.isFinite ? max(10, duration) : nil
        }
        return result
    }
}
