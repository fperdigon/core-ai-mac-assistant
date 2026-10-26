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
import MacPocketKnifeCore

/// Mutable call records are protected by the lock, including calls from deinit.
final class FakeSleepAssertionHolder: SleepAssertionHolding, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    private var handles: [SleepHandle] = []
    private let failsCreation: Bool

    init(failsCreation: Bool = false) {
        self.failsCreation = failsCreation
    }

    var createdNames: [String] { lock.withLock { names } }
    var releasedHandles: [SleepHandle] { lock.withLock { handles } }

    func create(name: String) -> SleepHandle? {
        lock.withLock {
            names.append(name)
            return failsCreation ? nil : SleepHandle(rawValue: UInt32(names.count))
        }
    }

    func release(_ handle: SleepHandle) {
        lock.withLock { handles.append(handle) }
    }
}

@MainActor
final class FakeKeepAwakeStateStore: KeepAwakeStateStore {
    var state: KeepAwakeState?

    init(state: KeepAwakeState? = nil) {
        self.state = state
    }

    func load() -> KeepAwakeState? { state }
    func save(_ state: KeepAwakeState?) { self.state = state }
}

@MainActor
final class FakeKeepAwakeScheduler: KeepAwakeScheduling {
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private struct Entry {
        let date: Date
        let action: @MainActor @Sendable () -> Void
        let cancellation: Cancellation
    }

    private(set) var now = Date(timeIntervalSince1970: 1_000)
    private var entries: [Entry] = []
    var pendingCount: Int { entries.filter { !$0.cancellation.isCancelled }.count }

    func schedule(
        at date: Date,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let cancellation = Cancellation()
        entries.append(Entry(date: date, action: action, cancellation: cancellation))
        return { cancellation.cancel() }
    }

    func advance(by interval: TimeInterval, includingCancelled: Bool = false) {
        now = now.addingTimeInterval(interval)
        let due = entries.filter { $0.date <= now }.sorted { $0.date < $1.date }
        entries.removeAll { $0.date <= now }
        for entry in due where includingCancelled || !entry.cancellation.isCancelled {
            entry.action()
        }
    }
}
