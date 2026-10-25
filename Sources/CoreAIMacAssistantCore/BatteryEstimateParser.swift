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

public enum BatteryEstimateParser {
    public static func parse(
        _ properties: [String: Any],
        powerSourceDescription: [String: Any]? = nil
    ) -> BatteryEstimate {
        let charging = properties["IsCharging"] as? Bool ?? false
        let connected = properties["ExternalConnected"] as? Bool ?? charging
        let full = properties["FullyCharged"] as? Bool ?? false
        let discharging = !connected && !charging
        let amperage = signedAmperage(properties["Amperage"])
            ?? signedAmperage(properties["InstantAmperage"])
        var watts: Double?
        if let amperage, let voltage = positiveNumber(properties["Voltage"]) {
            watts = positive(amperage * voltage / 1_000_000)
        }

        var seconds: TimeInterval?
        if charging && !full {
            seconds = minutes(powerSourceDescription?["Time to Full Charge"])
                ?? minutes(properties["AvgTimeToFull"])
                ?? minutes(properties["TimeRemaining"])
        } else if discharging {
            seconds = minutes(powerSourceDescription?["Time to Empty"])
                ?? minutes(properties["TimeRemaining"])
                ?? minutes(properties["AvgTimeToEmpty"])
            // CurrentCapacity may be a percentage; only raw capacity is known to be mAh.
            if seconds == nil, let amperage,
               let capacity = positiveNumber(properties["AppleRawCurrentCapacity"]) {
                seconds = positive(capacity / amperage * 3_600)
            }
        }
        return BatteryEstimate(timeRemaining: seconds, powerWatts: watts)
    }

    private static func signedAmperage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        // IOKit represents negative current as an unsigned two's-complement integer.
        let signed = Int64(bitPattern: number.uint64Value)
        return positive(abs(Double(signed)))
    }

    private static func minutes(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue >= 0,
              number.doubleValue != 65_535
        else { return nil }
        let minutesValue = number.doubleValue
        return positive(minutesValue * 60)
    }

    private static func positiveNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return positive(number.doubleValue)
    }

    private static func positive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }
}
