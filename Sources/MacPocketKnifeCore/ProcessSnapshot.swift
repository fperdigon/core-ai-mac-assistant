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

public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let name: String
    public let hasControllingTerminal: Bool
    public let userID: UInt32?

    public init(
        pid: Int32, parentPID: Int32, name: String, hasControllingTerminal: Bool,
        userID: UInt32? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.hasControllingTerminal = hasControllingTerminal
        self.userID = userID
    }
}
