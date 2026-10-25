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

@MainActor
public protocol KeepAwakeScheduling: Sendable {
    var now: Date { get }

    /// Runs the action later on the main actor. The returned closure cancels it.
    func schedule(
        at date: Date,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void
}

@MainActor
public struct KeepAwakeScheduler: KeepAwakeScheduling {
    public init() {}

    public var now: Date { Date() }

    public func schedule(
        at date: Date,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let delay = max(0, date.timeIntervalSince(now))
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
                action()
            } catch {
                // Cancellation leaves the assertion under the controller's ownership.
            }
        }
        return { task.cancel() }
    }
}
