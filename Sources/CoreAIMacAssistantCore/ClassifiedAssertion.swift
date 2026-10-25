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

public struct ClassifiedAssertion: Sendable, Equatable {
    public let assertion: SleepAssertion
    public let origin: ProcessOrigin
    public let isOwnedByCurrentUser: Bool
    public let isOwnAppAssertion: Bool

    public init(
        assertion: SleepAssertion, origin: ProcessOrigin,
        isOwnedByCurrentUser: Bool, isOwnAppAssertion: Bool
    ) {
        self.assertion = assertion
        self.origin = origin
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        self.isOwnAppAssertion = isOwnAppAssertion
    }
}
