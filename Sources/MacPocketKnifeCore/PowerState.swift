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

public enum PowerSource: Equatable, Sendable {
    case ac
    case battery
}

public struct PowerState: Equatable, Sendable {
    public let source: PowerSource
    public let batteryPercent: Int?
    public let isCharging: Bool

    public init(source: PowerSource, batteryPercent: Int?, isCharging: Bool) {
        self.source = source
        self.batteryPercent = batteryPercent.map { min(100, max(0, $0)) }
        self.isCharging = isCharging
    }
}
