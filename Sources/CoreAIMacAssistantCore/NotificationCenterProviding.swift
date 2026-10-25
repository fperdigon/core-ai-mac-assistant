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

@preconcurrency import UserNotifications

public enum AuthorizationState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// Main-actor isolation keeps notification framework objects inside the adapter boundary.
@MainActor
public protocol NotificationCenterProviding: Sendable {
    func authorizationStatus() async -> AuthorizationState
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
struct SystemNotificationCenterProvider: NotificationCenterProviding {
    private let center: UNUserNotificationCenter

    init() {
        center = .current()
    }

    func authorizationStatus() async -> AuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}
