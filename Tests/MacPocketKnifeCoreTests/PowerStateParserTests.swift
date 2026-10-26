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
import IOKit.ps
import Testing
import MacPocketKnifeCore

@Test func parsesACCharging() {
    let state = PowerStateParser.parse([
        kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSCurrentCapacityKey: 30,
        kIOPSMaxCapacityKey: 60,
        kIOPSIsChargingKey: true,
    ])
    #expect(state == PowerState(source: .ac, batteryPercent: 50, isCharging: true))
}

@Test func parsesBatteryDischarging() {
    let state = PowerStateParser.parse([
        kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        kIOPSCurrentCapacityKey: 20,
        kIOPSMaxCapacityKey: 60,
        kIOPSIsChargingKey: false,
    ])
    #expect(state == PowerState(source: .battery, batteryPercent: 33, isCharging: false))
}

@Test func parsesFullBattery() {
    let state = PowerStateParser.parse([
        kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSCurrentCapacityKey: 80,
        kIOPSMaxCapacityKey: 80,
        kIOPSIsChargingKey: false,
    ])
    #expect(state == PowerState(source: .ac, batteryPercent: 100, isCharging: false))
}

@Test func handlesMissingCapacityKeys() {
    for capacities: [String: Any] in [
        [:],
        [kIOPSCurrentCapacityKey: 50],
        [kIOPSMaxCapacityKey: 100],
    ] {
        var description = capacities
        description[kIOPSPowerSourceStateKey] = kIOPSBatteryPowerValue
        let state = PowerStateParser.parse(description)
        #expect(state == PowerState(source: .battery, batteryPercent: nil, isCharging: false))
    }
    #expect(PowerStateParser.parse([:]) == PowerState(
        source: .ac, batteryPercent: nil, isCharging: false
    ))
}

@Test func handlesZeroMaxCapacity() {
    let state = PowerStateParser.parse([
        kIOPSCurrentCapacityKey: 50,
        kIOPSMaxCapacityKey: 0,
    ])
    #expect(state.batteryPercent == nil)
}

@Test(arguments: [-10, 150]) func clampsBatteryPercent(current: Int) {
    let state = PowerStateParser.parse([
        kIOPSCurrentCapacityKey: current,
        kIOPSMaxCapacityKey: 100,
    ])
    #expect(state.batteryPercent == (current < 0 ? 0 : 100))
}

@Test func handlesInvalidCapacityValues() {
    for current: Any in ["unknown", Double.nan, Double.infinity] {
        let state = PowerStateParser.parse([
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: 100,
        ])
        #expect(state.batteryPercent == nil)
    }
    #expect(PowerStateParser.parse([
        kIOPSCurrentCapacityKey: 50,
        kIOPSMaxCapacityKey: -1,
    ]).batteryPercent == nil)
}
