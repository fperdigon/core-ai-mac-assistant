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

import CoreAIMacAssistantCore
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let checkForUpdates: () -> Void
    @State private var token = ""
    @State private var createBot = false
    @State private var isBusy = false
    @State private var status: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        Form {
            generalSection
            alertsSection
            Section("Kill rule") {
                Stepper(
                    "Release keep-awake and stop eligible caffeinate processes at: \(model.settings.policy.killThresholdPercent)%",
                    value: Binding(
                        get: { model.settings.policy.killThresholdPercent },
                        set: { value in
                            let policy = model.settings.policy
                            model.settings.policy = PolicySettings(
                                killThresholdPercent: value,
                                maxKillsPerWindow: policy.maxKillsPerWindow,
                                killWindow: policy.killWindow
                            )
                        }
                    ), in: 5...50
                )
            }
            telegramSection
            UpdatesSettingsSection(
                channel: Binding(
                    get: { model.settings.updateChannel },
                    set: { model.settings.updateChannel = $0; model.settings.skippedVersion = nil }
                ),
                automatically: $model.settings.checkForUpdatesAutomatically,
                checkNow: checkForUpdates
            )
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 580, minHeight: 680)
        .onDisappear {
            operation?.cancel()
            token = ""
        }
        .onReceive(model.$settings) { settings in
            if !settings.telegram.isEnabled { operation?.cancel() }
        }
        .onReceive(model.$launchAtLoginStatus) { message in
            if let message { status = message }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Keep awake indefinitely by default", isOn: $model.keepAwakeIndefinitely)
            if model.settings.keepAwakeDefaultDuration != nil {
                TextField("Default keep-awake duration (seconds)", value: Binding(
                    get: { model.settings.keepAwakeDefaultDuration ?? 3600 },
                    set: { model.settings.keepAwakeDefaultDuration = $0 }
                ), format: .number)
            }
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Text("Local notifications are always enabled.")
                .font(.caption)
        }
    }

    private var alertsSection: some View {
        Section("Alerts") {
            Stepper("Urgent below: \(model.settings.alerts.urgentBelowPercent)%", value: Binding(
                get: { model.settings.alerts.urgentBelowPercent },
                set: { updateAlerts(urgent: $0) }
            ), in: 2...100)
            Stepper("Critical below: \(model.settings.alerts.criticalBelowPercent)%", value: Binding(
                get: { model.settings.alerts.criticalBelowPercent },
                set: { updateAlerts(critical: $0) }
            ), in: 1...(model.settings.alerts.urgentBelowPercent - 1))
            TextField("Normal interval (seconds)", value: Binding(
                get: { model.settings.alerts.normalInterval },
                set: { updateAlerts(normalInterval: $0) }
            ), format: .number)
            TextField("Urgent interval (seconds)", value: Binding(
                get: { model.settings.alerts.urgentInterval },
                set: { updateAlerts(urgentInterval: $0) }
            ), format: .number)
            TextField("Critical interval (seconds)", value: Binding(
                get: { model.settings.alerts.criticalInterval },
                set: { updateAlerts(criticalInterval: $0) }
            ), format: .number)
            Text("Intervals must be at least 10 seconds.").font(.caption)
            Button("Reset to defaults") { model.resetAlertsToDefaults() }
        }
    }

    private var telegramSection: some View {
        Section("Telegram") {
            Toggle("Enable Telegram", isOn: $model.settings.telegram.isEnabled)
            Group {
                Picker("Bot setup", selection: $createBot) {
                    Text("Use existing bot").tag(false)
                    Text("Create a new bot").tag(true)
                }
                if createBot {
                    Text("1. Open Telegram and find the verified @BotFather.\n2. Send /newbot and follow the instructions to choose a name and username.\n3. Paste the bot token below, then validate and save it.")
                        .font(.callout)
                }
                SecureField("Bot token", text: $token)
                Button("Validate and save token") {
                    let candidate = token
                    token = ""
                    run("Bot validated. Token saved securely.") {
                        _ = try await model.validateAndSaveTelegramToken(candidate)
                    }
                }
                .disabled(token.isEmpty || isBusy)
                TextField("Chat ID", text: Binding(
                    get: { model.settings.telegram.chatID ?? "" },
                    set: { model.settings.telegram.chatID = $0.isEmpty ? nil : $0 }
                ))
                Text("Start discovery, then open your bot in Telegram and send /start. Discovery waits up to 60 seconds for a new message.")
                    .font(.caption)
                HStack {
                    Button("Discover chat ID") {
                        run("Chat ID discovered.") { _ = try await model.discoverTelegramChatID() }
                    }
                    .disabled(isBusy)
                    Button("Send test message") {
                        run("Test message sent.") { try await model.sendTelegramTestMessage() }
                    }
                    .disabled(isBusy)
                    if isBusy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { operation?.cancel() }
                    }
                }
                Toggle("Silent mode", isOn: $model.settings.telegram.silentMode)
                Toggle("Include machine name", isOn: $model.settings.telegram.includeMachineName)
                Text("Messages respect the phone’s silent and Do Not Disturb settings. The token is stored only in the Keychain.")
                    .font(.caption)
            }
            .disabled(!model.settings.telegram.isEnabled)
            if let status { Text(status).font(.callout).accessibilityLabel(status) }
        }
    }

    private func updateAlerts(
        urgent: Int? = nil, critical: Int? = nil, normalInterval: Double? = nil,
        urgentInterval: Double? = nil, criticalInterval: Double? = nil
    ) {
        let alerts = model.settings.alerts
        model.settings.alerts = AlertSettings(
            urgentBelowPercent: urgent ?? alerts.urgentBelowPercent,
            criticalBelowPercent: critical ?? alerts.criticalBelowPercent,
            normalInterval: normalInterval ?? alerts.normalInterval,
            urgentInterval: urgentInterval ?? alerts.urgentInterval,
            criticalInterval: criticalInterval ?? alerts.criticalInterval
        )
    }

    private func run(_ success: String, action: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        status = nil
        operation = Task { @MainActor in
            defer { isBusy = false }
            do {
                try await action()
                try Task.checkCancellation()
                status = success
            } catch is CancellationError {
                status = "Telegram setup cancelled."
            } catch {
                // Avoid displaying transport or credential-bearing error descriptions.
                status = "Telegram setup failed. Check the bot token, chat ID, and connection, then try again."
            }
        }
    }
}
