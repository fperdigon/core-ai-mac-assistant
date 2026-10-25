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

@MainActor
private final class NotifierSettings: AssistantSettingsProviding {
    var settings = AppSettings()
}

@MainActor
private final class DeliveredNotices: AlertNotifying {
    var values: [Notice] = []
    var onDelivery: (@MainActor () -> Void)?
    func deliver(_ notice: Notice) async {
        values.append(notice)
        onDelivery?()
    }
}

private let notifierNotice = Notice(kind: .info, title: "Keep-awake status", body: "Sleep assertion released.")

@Test(arguments: ["disabled", "missing token", "missing chat", "transport failure"])
@MainActor func telegramUnavailableNeverAffectsLocalDelivery(scenario: String) async throws {
    let settings = NotifierSettings()
    settings.settings.telegram = TelegramPreferences(isEnabled: scenario != "disabled", chatID: "-42")
    if scenario == "missing chat" { settings.settings.telegram.chatID = nil }
    let secrets = InMemorySecretStore()
    if scenario != "missing token" { try secrets.setSecret("synthetic-credential", for: .telegramBotToken) }
    let transport = FakeTelegramTransport(failure: TelegramError.network)
    let local = DeliveredNotices()
    let telegram = TelegramNotifier(settings: settings, secrets: secrets, transport: transport,
                                    machineName: { Issue.record("Machine name is opt-in"); return nil })
    // Telegram comes first deliberately: local must still receive every notice.
    await CompositeNotifier(channels: [telegram, local]).deliver(notifierNotice)
    #expect(local.values == [notifierNotice])
    #expect(await transport.requests.count == (scenario == "transport failure" ? 1 : 0))
}

@Test @MainActor func telegramUsesCurrentPreferencesAndComposedNotice() async throws {
    let settings = NotifierSettings()
    let secrets = InMemorySecretStore()
    try secrets.setSecret("synthetic-credential", for: .telegramBotToken)
    let response = #"{"ok":true,"result":{"chat":{"id":-42},"text":"Delivered"}}"#
    let transport = FakeTelegramTransport([.init(response), .init(response)])
    let notifier = TelegramNotifier(settings: settings, secrets: secrets, transport: transport,
                                   machineName: { "Example Mac" })
    await notifier.deliver(notifierNotice)
    #expect(await transport.requests.isEmpty)
    settings.settings.telegram = TelegramPreferences(isEnabled: true, chatID: "-42", silentMode: true)
    await notifier.deliver(notifierNotice)
    settings.settings.telegram.silentMode = false
    settings.settings.telegram.includeMachineName = true
    await notifier.deliver(notifierNotice)
    let requests = await transport.requests
    #expect(requests.count == 2)
    let firstData = try #require(requests[0].httpBody)
    let secondData = try #require(requests[1].httpBody)
    let first = try #require(JSONSerialization.jsonObject(with: firstData) as? [String: Any])
    let second = try #require(JSONSerialization.jsonObject(with: secondData) as? [String: Any])
    #expect(first["disable_notification"] as? Bool == true)
    #expect(first["text"] as? String == "Keep-awake status\nSleep assertion released.")
    #expect(second["disable_notification"] as? Bool == false)
    #expect(second["text"] as? String == "Keep-awake status (Example Mac)\nSleep assertion released.")
}

@MainActor
private final class SuspendedNotifier: AlertNotifying {
    var continuation: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    func deliver(_ notice: Notice) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
}

@Test @MainActor func compositeDeliversLocallyWhileAnotherChannelIsSuspended() async {
    let suspended = SuspendedNotifier()
    let local = DeliveredNotices()
    let delivery = Task {
        await CompositeNotifier(channels: [suspended, local]).deliver(notifierNotice)
    }
    if suspended.continuation == nil {
        await withCheckedContinuation { suspended.started = $0 }
    }
    if local.values.isEmpty {
        await withCheckedContinuation { continuation in
            local.onDelivery = { continuation.resume() }
        }
    }
    local.onDelivery = nil
    #expect(local.values == [notifierNotice])
    suspended.continuation?.resume()
    await delivery.value
}
