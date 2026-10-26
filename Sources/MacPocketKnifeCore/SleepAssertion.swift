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

public struct SleepAssertion: Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let type: String
    public let name: String

    public init(pid: Int32, processName: String, type: String, name: String) {
        self.pid = pid
        self.processName = processName
        self.type = type
        self.name = name
    }

    public var isCaffeinate: Bool {
        processName == "caffeinate"
    }
}
