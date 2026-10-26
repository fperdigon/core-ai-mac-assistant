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

import Testing
@testable import MacPocketKnifeCore

@Test func aboutVersionFormatting() {
    #expect(BuildInfo.aboutVersion(version: "0.1.0", sha: "02f77a0123456789", channel: "stable") == "0.1.0")
    #expect(BuildInfo.aboutVersion(version: "0.1.0", sha: "02f77a0123456789", channel: "nightly") == "0.1.0 (02f77a0)")
    #expect(BuildInfo.aboutVersion(version: "0.1.0", sha: "02f77a0123456789", channel: "dev") == "0.1.0 (02f77a0)")
    #expect(BuildInfo.aboutVersion(version: "0.1.0", sha: "unknown", channel: "nightly") == "0.1.0")
    #expect(BuildInfo.aboutVersion(version: "0.1.0", sha: "abc", channel: "dev") == "0.1.0 (abc)")
}
