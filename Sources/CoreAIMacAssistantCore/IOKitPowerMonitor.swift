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
import IOKit.ps

@MainActor
public final class IOKitPowerMonitor: PowerMonitoring {
    public private(set) var current: PowerState

    private var handler: (@Sendable (PowerState) -> Void)?
    private var observation: RunLoopObservation?

    public init() {
        current = Self.readState()
    }

    public func start(_ handler: @escaping @Sendable (PowerState) -> Void) {
        self.handler = handler
        guard observation == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<IOKitPowerMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.refresh()
            }
        }, context)?.takeRetainedValue() else {
            return
        }
        observation = RunLoopObservation(source)
        refresh()
    }

    public func stop() {
        handler = nil
        observation = nil
    }

    /// Owns the source so releasing a monitor also removes its callback.
    private final class RunLoopObservation {
        let source: CFRunLoopSource

        init(_ source: CFRunLoopSource) {
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        deinit {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
    }

    private func refresh() {
        let state = Self.readState()
        guard state != current else { return }
        current = state
        handler?(state)
    }

    private static func readState() -> PowerState {
        let noBattery = PowerState(source: .ac, batteryPercent: nil, isCharging: false)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return noBattery
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }
            return PowerStateParser.parse(description)
        }
        return noBattery
    }
}
