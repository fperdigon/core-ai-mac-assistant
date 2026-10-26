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
import IOKit
import IOKit.ps

public struct IOKitBatteryEstimator: BatteryEstimating {
    public init() {}

    public func currentEstimate() -> BatteryEstimate {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        var properties: [String: Any] = [:]
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var result: Unmanaged<CFMutableDictionary>?
            let status = IORegistryEntryCreateCFProperties(
                service, &result, kCFAllocatorDefault, 0
            )
            let dictionary = result?.takeRetainedValue()
            if status == kIOReturnSuccess, let values = dictionary as? [String: Any] {
                properties = values
            }
        }

        let sourceDescription = Self.internalBatteryDescription()
        return BatteryEstimateParser.parse(
            properties, powerSourceDescription: sourceDescription
        )
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType
            else { continue }
            return description
        }
        return nil
    }
}
