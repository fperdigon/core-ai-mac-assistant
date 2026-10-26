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

@MainActor
public protocol AssistantClock: Sendable {
    var now: Date { get }
}

public struct SystemAssistantClock: AssistantClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public protocol AssistantTickScheduling: Sendable {
    func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> @Sendable () -> Void
}

public struct AssistantTickScheduler: AssistantTickScheduling {
    public init() {}

    public func schedule(
        every interval: TimeInterval,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> @Sendable () -> Void {
        let task = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    try Task.checkCancellation()
                } catch { return }
                await action()
            }
        }
        return { task.cancel() }
    }
}

@MainActor
public protocol AssistantSettingsProviding {
    var settings: AppSettings { get }
}

extension SettingsModel: AssistantSettingsProviding {}

public protocol ProcessClassifying: Sendable {
    func origin(of pid: Int32) -> ProcessOrigin
    func isOwnedByCurrentUser(_ pid: Int32, currentUserID: UInt32) -> Bool
}

extension ProcessClassifier: ProcessClassifying {}
