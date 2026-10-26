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
import MacPocketKnifeCore

private func summaryAssertion(_ name: String, pid: Int32 = 42) -> SleepAssertion {
    SleepAssertion(pid: pid, processName: name, type: "PreventSystemSleep", name: "Keep awake")
}

@Test func sleepBlockerSummaryExcludesEveryOwnPIDAssertionAndMacOSInternals() {
    let assertions = [
        summaryAssertion("MacPocketKnife", pid: 99),
        summaryAssertion("Different assertion", pid: 99),
        summaryAssertion("powerd"), summaryAssertion("WindowServer"),
        summaryAssertion("loginwindow"), summaryAssertion("sharingd"),
        summaryAssertion(""),
    ]
    #expect(SleepBlockerSummary.names(assertions: assertions, ownPID: 99).isEmpty)
    #expect(SleepBlockerSummary.names(assertions: [], ownPID: 99).isEmpty)
}

@Test func sleepBlockerSummaryMapsDeduplicatesAndSortsUserActions() {
    let assertions = [
        summaryAssertion("coreaudiod"), summaryAssertion("Claude"),
        summaryAssertion("Claude", pid: 43), summaryAssertion("audio playback"),
        summaryAssertion("UnknownApp"),
    ]
    let names = SleepBlockerSummary.names(assertions: assertions, ownPID: 99)
    #expect(names == ["Claude", "UnknownApp", "audio playback"])
    #expect(StatusLineFormatter.blockersLine(blockers: names)
        == "Also keeping awake: Claude, UnknownApp, audio playback")
    #expect(StatusLineFormatter.blockersLine(blockers: []) == nil)
}

@Test func sleepBlockerSummaryLimitsDistinctNamesAfterFilteringAndSorting() {
    let assertions = ["Z", "D", "C", "B", "A", "A", "powerd"].map { summaryAssertion($0) }
    let names = SleepBlockerSummary.names(assertions: assertions, ownPID: 99)
    #expect(names == ["A", "B", "C", "+2 more"])
    let four = ["D", "C", "B", "A"].map { summaryAssertion($0) }
    #expect(SleepBlockerSummary.names(assertions: four, ownPID: 99) == ["A", "B", "C", "+1 more"])
}

@Test func batteryAlertFormattersUseTheSameCleanedSummary() {
    let assertions = [
        summaryAssertion("Claude"), summaryAssertion("coreaudiod"),
        summaryAssertion("powerd"), summaryAssertion("MacPocketKnife", pid: 99),
    ]
    let names = SleepBlockerSummary.names(assertions: assertions, ownPID: 99)
    let alert = BatteryAlert(level: .normal, batteryPercent: 25)
    let notice = NoticeComposer().compose(alert: alert, blockers: names)
    let telegram = TelegramAlertFormatter().format(alert: alert, blockers: names)
    #expect(notice.body == "Battery at 25%. Keeping the Mac awake: Claude, audio playback.")
    #expect(telegram == "Normal: battery at 25%. Keeping the Mac awake: Claude, audio playback.")
    let rawNames = ["powerd", "coreaudiod"]
    #expect(NoticeComposer().compose(alert: alert, blockers: rawNames).body
        == "Battery at 25%. Keeping the Mac awake: audio playback.")
    #expect(TelegramAlertFormatter().format(alert: alert, blockers: rawNames)
        == "Normal: battery at 25%. Keeping the Mac awake: audio playback.")
}
