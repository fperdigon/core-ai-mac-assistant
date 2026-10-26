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

@Test(arguments: [
    (AlertLevel.normal, "Battery alert"),
    (.urgent, "Urgent battery alert"),
    (.critical, "Critical battery alert"),
])
func noticeComposerFormatsEveryBatteryLevel(level: AlertLevel, title: String) {
    let composer: any NoticeComposing = NoticeComposer()
    #expect(composer.compose(
        alert: BatteryAlert(level: level, batteryPercent: 25),
        blockers: ["caffeinate", "MediaPlayer"]
    ) == Notice(
        kind: .batteryAlert, title: title,
        body: "Battery at 25%. Keeping the Mac awake: caffeinate, MediaPlayer.", level: level
    ))
}

@Test func noticeComposerHandlesMissingAndEmptyBlockerNames() {
    let composer = NoticeComposer()
    let alert = BatteryAlert(level: .normal, batteryPercent: 80)
    #expect(composer.compose(alert: alert).body
        == "Battery at 80%. Keeping the Mac awake: an active sleep assertion.")
    #expect(composer.compose(alert: alert, blockers: [""]) == composer.compose(alert: alert))
    #expect(composer.compose(alert: alert, blockers: ["", "caffeinate"]).body
        == "Battery at 80%. Keeping the Mac awake: caffeinate.")
}

private func noticeAssertion(name: String) -> ClassifiedAssertion {
    ClassifiedAssertion(
        assertion: SleepAssertion(
            pid: 42, processName: name, type: "PreventSystemSleep", name: "Keep awake"
        ),
        origin: .app, isOwnedByCurrentUser: true, isOwnAppAssertion: false
    )
}

@Test func noticeComposerFormatsEveryPolicyActionAndReason() {
    let cases: [(PolicyAction, Notice)] = [
        (.notifyDetected(noticeAssertion(name: "caffeinate")), Notice(
            kind: .keepAwakeDetected, title: "Keep-awake process detected",
            body: "caffeinate (PID 42) is keeping the Mac awake."
        )),
        (.notifyReportOnly(noticeAssertion(name: "MediaPlayer")), Notice(
            kind: .keepAwakeDetected, title: "Sleep blocker reported",
            body: "MediaPlayer (PID 42) is keeping the Mac awake. Report only."
        )),
        (.terminate(pid: 42, processName: "caffeinate", reason: .consoleStarted), Notice(
            kind: .processTerminated, title: "Keep-awake process terminated",
            body: "caffeinate (PID 42) terminated: started from a console."
        )),
        (.terminate(pid: 42, processName: "caffeinate", reason: .batteryThreshold), Notice(
            kind: .processTerminated, title: "Keep-awake process terminated",
            body: "caffeinate (PID 42) terminated: battery threshold reached."
        )),
        (.notifyTerminationSkipped(pid: 42, reason: .notOwnedByCurrentUser), Notice(
            kind: .terminationSkipped, title: "Termination skipped",
            body: "PID 42: not owned by the current user."
        )),
        (.notifyTerminationSkipped(pid: 42, reason: .killLoopLimit), Notice(
            kind: .terminationSkipped, title: "Termination skipped",
            body: "PID 42: termination retry limit reached."
        )),
        (.releaseOwnAssertion, Notice(
            kind: .info, title: "Keep-awake released",
            body: "The app's sleep assertion was released: battery threshold reached."
        )),
    ]
    let composer: any NoticeComposing = NoticeComposer()
    for (action, expected) in cases {
        #expect(composer.compose(action: action) == expected)
    }
}
