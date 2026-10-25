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

public struct KeepAwakeState: Codable, Equatable, Sendable {
    public let isActive: Bool
    public let expiryDate: Date?

    public init(isActive: Bool, expiryDate: Date? = nil) {
        self.isActive = isActive
        self.expiryDate = expiryDate
    }
}

@MainActor
public protocol KeepAwakeStateStore: Sendable {
    func load() -> KeepAwakeState?
    /// Saving nil clears the saved state.
    func save(_ state: KeepAwakeState?)
}

@MainActor
public final class UserDefaultsKeepAwakeStateStore: KeepAwakeStateStore {
    private let defaults: UserDefaults
    private let key = "keepAwakeState"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> KeepAwakeState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeepAwakeState.self, from: data)
    }

    public func save(_ state: KeepAwakeState?) {
        guard let state, let data = try? JSONEncoder().encode(state) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
