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

import Testing
import CoreAIMacAssistantCore

@MainActor
private final class PowerEvents {
    var states: [PowerState] = []
}

@Test @MainActor func fakeMonitorOnlyEmitsChanges() {
    let initial = PowerState(source: .ac, batteryPercent: 80, isCharging: true)
    let unplugged = PowerState(source: .battery, batteryPercent: 80, isCharging: false)
    let discharged = PowerState(source: .battery, batteryPercent: 79, isCharging: false)
    let monitor = FakePowerMonitor(current: initial)
    let events = PowerEvents()
    monitor.start { state in
        MainActor.assumeIsolated { events.states.append(state) }
    }
    #expect(events.states.isEmpty)
    monitor.push(initial)
    monitor.push(unplugged)
    monitor.push(unplugged)
    monitor.push(discharged)
    #expect(events.states == [unplugged, discharged])
    #expect(monitor.current == discharged)
}

@Test @MainActor func fakeMonitorStopsEvents() {
    let initial = PowerState(source: .ac, batteryPercent: 100, isCharging: false)
    let unplugged = PowerState(source: .battery, batteryPercent: 100, isCharging: false)
    let monitor = FakePowerMonitor(current: initial)
    let events = PowerEvents()
    monitor.start { state in
        MainActor.assumeIsolated { events.states.append(state) }
    }
    monitor.stop()
    monitor.stop()
    monitor.push(unplugged)
    #expect(events.states.isEmpty)
    #expect(monitor.current == unplugged)
}

@Test @MainActor func fakeMonitorCanRestartWithANewHandler() {
    let initial = PowerState(source: .ac, batteryPercent: nil, isCharging: false)
    let changed = PowerState(source: .battery, batteryPercent: 50, isCharging: false)
    let monitor = FakePowerMonitor(current: initial)
    let oldEvents = PowerEvents()
    let newEvents = PowerEvents()
    monitor.start { state in
        MainActor.assumeIsolated { oldEvents.states.append(state) }
    }
    monitor.stop()
    monitor.start { state in
        MainActor.assumeIsolated { newEvents.states.append(state) }
    }
    monitor.push(changed)
    #expect(oldEvents.states.isEmpty)
    #expect(newEvents.states == [changed])
}
