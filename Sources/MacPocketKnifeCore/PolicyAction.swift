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

public enum TerminationReason: Sendable, Equatable {
    case consoleStarted
    case batteryThreshold
}

public enum TerminationSkipReason: Sendable, Equatable {
    case notOwnedByCurrentUser
    case killLoopLimit
}

public enum PolicyAction: Sendable, Equatable {
    case terminate(pid: Int32, processName: String, reason: TerminationReason)
    case releaseOwnAssertion
    case notifyDetected(ClassifiedAssertion)
    case notifyTerminationSkipped(pid: Int32, reason: TerminationSkipReason)
}
