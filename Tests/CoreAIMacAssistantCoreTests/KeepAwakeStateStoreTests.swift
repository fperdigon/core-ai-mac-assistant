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

@Test @MainActor func keepAwakeUserDefaultsStoreRoundTripsAndClears() throws {
    let suite = "KeepAwakeStateStoreTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = UserDefaultsKeepAwakeStateStore(defaults: defaults)
    #expect(store.load() == nil)
    let timed = KeepAwakeState(isActive: true, expiryDate: Date(timeIntervalSince1970: 2_000))
    store.save(timed)
    let reopened = UserDefaultsKeepAwakeStateStore(defaults: defaults)
    #expect(reopened.load() == timed)
    store.save(KeepAwakeState(isActive: true))
    #expect(reopened.load() == KeepAwakeState(isActive: true))
    store.save(KeepAwakeState(isActive: false))
    #expect(reopened.load() == KeepAwakeState(isActive: false))
    store.save(nil)
    #expect(reopened.load() == nil)
}
