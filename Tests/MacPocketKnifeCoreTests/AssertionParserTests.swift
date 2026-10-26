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
import Testing
import MacPocketKnifeCore

@Test func caffeinateAssertionIncludesOwnerAndDetails() {
    let assertions = AssertionParser.parse([
        42: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Keep awake", "AssertLevel": 255]],
    ]) { pid in
        pid == 42 ? "caffeinate" : nil
    }

    #expect(assertions == [SleepAssertion(
        pid: 42, processName: "caffeinate", type: "PreventUserIdleSystemSleep", name: "Keep awake"
    )])
    #expect(assertions.first?.isCaffeinate == true)
}

@Test func otherAppsAreReportedWithoutCaffeinateFlag() {
    let assertions = AssertionParser.parse([
        43: [["AssertType": "PreventSystemSleep", "AssertName": "Playback"]],
    ]) { _ in "MediaPlayer" }

    #expect(assertions.count == 1)
    #expect(assertions.first?.processName == "MediaPlayer")
    #expect(assertions.first?.isCaffeinate == false)
    #expect(SleepAssertion(pid: 44, processName: "Caffeinate", type: "PreventSystemSleep", name: "").isCaffeinate == false)
}

@Test func nonSleepAndTurnedOffAssertionsAreIgnored() {
    let assertions = AssertionParser.parse([
        42: [
            ["AssertType": "BackgroundTask", "AssertLevel": 255],
            ["AssertType": "PreventSystemSleep", "AssertLevel": 0],
            ["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 0],
            ["AssertName": "Missing type", "AssertLevel": 255],
        ],
    ]) { _ in "caffeinate" }

    #expect(assertions.isEmpty)
}

@Test func severalSleepAssertionsFromOneProcessAreReported() {
    let types = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion", "NoDisplaySleepAssertion", "PreventDiskIdle",
    ]
    let entries: [[String: Any]] = types.map {
        ["AssertType": $0, "AssertName": $0, "AssertLevel": NSNumber(value: 255)]
    }
    let assertions = AssertionParser.parse([42: entries]) { _ in "ExampleApp" }

    #expect(assertions.map(\.type) == types.sorted())
    #expect(assertions.allSatisfy { $0.pid == 42 && $0.name == $0.type })
}

@Test func level255IsKeptAndLevelZeroIsDropped() {
    let assertions = AssertionParser.parse([
        42: [
            ["AssertType": "PreventSystemSleep", "AssertName": "On", "AssertLevel": 255],
            ["AssertType": "PreventSystemSleep", "AssertName": "Off", "AssertLevel": 0],
        ],
    ]) { _ in "ExampleApp" }

    #expect(assertions.map(\.name) == ["On"])
}

@Test func missingLevelIsKept() {
    let assertions = AssertionParser.parse([
        42: [["AssertType": "PreventSystemSleep", "AssertName": "No level"]],
    ]) { _ in "ExampleApp" }

    #expect(assertions.map(\.name) == ["No level"])
}

@Test func entryProcessNameIsPreferredOverClosure() {
    let assertions = AssertionParser.parse([
        42: [["AssertType": "PreventSystemSleep", "Process Name": "caffeinate"]],
    ]) { _ in
        Issue.record("The process name closure should not be called")
        return "OtherApp"
    }

    #expect(assertions.first?.processName == "caffeinate")
}

@Test func emptyEntryProcessNameFallsBackToClosureThenUnknown() {
    let withClosure = AssertionParser.parse([
        42: [["AssertType": "PreventSystemSleep", "Process Name": ""]],
    ]) { _ in "FallbackApp" }
    let withoutClosure = AssertionParser.parse([
        43: [["AssertType": "PreventSystemSleep", "Process Name": ""]],
    ]) { _ in nil }

    #expect(withClosure.first?.processName == "FallbackApp")
    #expect(withoutClosure.first?.processName == "unknown")
}

@Test func unknownProcessNameFallsBackToUnknown() {
    let assertions = AssertionParser.parse([
        99: [["AssertType": "PreventSystemSleep"]],
    ]) { _ in nil }

    #expect(assertions.first?.processName == "unknown")
    #expect(assertions.first?.pid == 99)
    #expect(assertions.first?.name == "")
}

@Test func assertionsHaveDeterministicOrdering() {
    let entries: [[String: Any]] = [
        ["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Z"],
        ["AssertType": "PreventSystemSleep", "AssertName": "B"],
        ["AssertType": "PreventSystemSleep", "AssertName": "A"],
    ]
    let first = AssertionParser.parse([
        20: entries, 10: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "First"]],
    ]) { _ in "ExampleApp" }
    let second = AssertionParser.parse([
        10: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "First"]],
        20: Array(entries.reversed()),
    ]) { _ in "ExampleApp" }

    #expect(first == second)
    #expect(first.map(\.pid) == [10, 20, 20, 20])
    #expect(first.map(\.name) == ["First", "A", "B", "Z"])
}

@Test func emptyAssertionInputIsEmpty() {
    let assertions = AssertionParser.parse([:]) { _ in
        Issue.record("Empty input should not resolve process names")
        return nil
    }
    #expect(assertions.isEmpty)
}

@Test func fakeAssertionProviderReturnsConfiguredAssertions() {
    var provider = FakeAssertionProvider()
    #expect(provider.currentAssertions().isEmpty)
    provider.assertions = [SleepAssertion(
        pid: 42, processName: "caffeinate", type: "PreventSystemSleep", name: "Keep awake"
    )]
    #expect(provider.currentAssertions() == provider.assertions)
}

@Test func iokitAssertionProviderSnapshotDoesNotCrash() {
    _ = IOKitAssertionProvider().currentAssertions()
}
