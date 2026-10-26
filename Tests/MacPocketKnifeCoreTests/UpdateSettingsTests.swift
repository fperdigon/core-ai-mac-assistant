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

@Test func updateSettingsRoundTripAndDefaults() throws {
    let defaults = AppSettings()
    #expect(defaults.updateChannel == .stable)
    #expect(defaults.checkForUpdatesAutomatically)
    #expect(defaults.skippedVersion == nil)
    let settings = AppSettings(updateChannel: .nightly, checkForUpdatesAutomatically: false,
                               skippedVersion: "nightly-20261025-abcdef1")
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
}

@Test func updateSettingsMigrateLegacyDocumentWithoutLosingPreferences() throws {
    var original = AppSettings()
    original.launchAtLogin = true
    original.keepAwakeDefaultDuration = 1800
    original.alerts = AlertSettings(urgentBelowPercent: 60)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    for key in ["updateChannel", "checkForUpdatesAutomatically", "skippedVersion"] { json.removeValue(forKey: key) }
    let migrated = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(migrated == original)
    json["updateChannel"] = NSNull()
    json["checkForUpdatesAutomatically"] = NSNull()
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json)) == original)
}
