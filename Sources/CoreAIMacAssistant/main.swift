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

import AppKit
import CoreAIMacAssistantCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let controller = CaffeinateController()
    private let localNotifier = LocalNotifier()
    private let settings = SettingsModel(
        store: UserDefaultsSettingsStore(defaults: .standard), secrets: KeychainSecretStore()
    )
    private lazy var updates = UpdateController(
        preferences: { [unowned self] in
            UpdatePreferences(channel: settings.settings.updateChannel,
                              automatically: settings.settings.checkForUpdatesAutomatically,
                              skippedVersion: settings.settings.skippedVersion)
        },
        skipVersion: { [unowned self] in settings.settings.skippedVersion = $0 },
        beforeQuit: { [unowned self] in
            // The controller saves every state change. Re-save the current deadline and flush
            // before quitting so the replacement restores precisely the same assertion state.
            let defaults = UserDefaults.standard
            let store = UserDefaultsKeepAwakeStateStore(defaults: defaults)
            store.save(controller.isActive ? KeepAwakeState(isActive: true, expiryDate: controller.expiryDate) : nil)
            defaults.synchronize()
        }
    )
    private var engine: AssistantEngine?
    private var settingsWindow: SettingsWindowController?
    private let statusLine = NSMenuItem(title: "Reading power state…", action: nil, keyEquivalent: "")
    private let keepAwake = NSMenuItem(title: "Keep awake", action: nil, keyEquivalent: "")
    private let authorization = NSMenuItem(title: "Notifications: checking…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        keepAwake.target = self
        keepAwake.action = #selector(toggleKeepAwake)
        menu.addItem(keepAwake)
        authorization.isEnabled = false
        menu.addItem(authorization)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(updates.menuItem())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item

        let engine = AssistantEngine(
            powerMonitor: IOKitPowerMonitor(), assertionProvider: IOKitAssertionProvider(),
            classifier: ProcessClassifier(processTable: SysctlProcessTable()),
            caffeinateController: controller,
            channels: [localNotifier, TelegramNotifier(settings: settings, secrets: KeychainSecretStore())],
            terminator: SignalProcessTerminator(), settings: settings
        )
        self.engine = engine
        engine.onChange = { [weak self] in self?.refreshStatus() }
        controller.restoreIfNeeded()
        updates.checkInBackgroundIfDue()
        controller.onChange = { [weak self] _ in
            self?.refreshStatus()
            Task { @MainActor [weak self] in await self?.engine?.evaluate() }
        }
        Task { @MainActor in
            await engine.start()
            // The system authorization state persists across launches.
            updateAuthorization(await localNotifier.requestAuthorizationIfNeeded())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
        Task { @MainActor in updateAuthorization(await localNotifier.authorizationState()) }
    }

    private func refreshStatus() {
        statusLine.title = engine?.statusText ?? "Reading power state…"
        keepAwake.state = controller.isActive ? .on : .off
    }

    private func updateAuthorization(_ state: AuthorizationState) {
        authorization.target = self
        authorization.action = nil
        authorization.isEnabled = false
        switch state {
        case .authorized: authorization.title = "Notifications: authorized"
        case .notDetermined: authorization.title = "Notifications: not requested"
        case .unavailable: authorization.title = "Notifications: unavailable"
        case .denied:
            authorization.title = "Notifications denied — Open System Settings…"
            authorization.action = #selector(openNotificationSettings)
            authorization.isEnabled = true
        }
    }

    @objc private func toggleKeepAwake() {
        if controller.isActive {
            controller.deactivate()
        } else {
            controller.activate(duration: settings.settings.keepAwakeDefaultDuration)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: settings, checkForUpdates: { [weak self] in self?.updates.checkNow() }) }
        settingsWindow?.show()
    }

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
NSApp.setActivationPolicy(.accessory)
application.run()
