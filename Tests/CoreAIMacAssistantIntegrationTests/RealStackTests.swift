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

import Darwin
import Testing
import CoreAIMacAssistantCore

@Suite(.serialized, .enabled(if: RealProcess.ptyAvailable,
                            "Requires forkpty and an available pseudo-terminal"))
@MainActor
struct RealStackTests {
    @Test(arguments: [PowerSource.ac, .battery])
    func consoleCaffeinateTerminatesInOneEvaluation(source: PowerSource) async throws {
        let process = try RealProcess.shell()
        defer { process.cleanup() }
        let assertions = OwnedAssertions(pid: process.pid)
        try eventually("assertion registration") { !assertions.currentAssertions().isEmpty }
        let snapshot = try #require(SysctlProcessTable().snapshot(of: process.pid))
        #expect(snapshot.hasControllingTerminal)
        let parent = try #require(SysctlProcessTable().snapshot(of: snapshot.parentPID))
        #expect(parent.name == "zsh")
        #expect(parent.hasControllingTerminal)
        #expect(ProcessClassifier().origin(of: process.pid) == .console)

        let fixture = IntegrationFixture(assertions: assertions, process: process, source: source)
        defer { fixture.stop() }
        await fixture.engine.start()
        #expect(fixture.notices.contains(.processTerminated, pid: process.pid))
        #expect(kill(process.pid, 0) == -1 && errno == ESRCH)
        try eventually("assertion release") { assertions.currentAssertions().isEmpty }
    }

    @Test(.enabled(if: RealProcess.runnerHasNoTerminal,
                   "Direct posix_spawn requires a test runner without a controlling terminal"))
    func appCaffeinateIsReportedUntilBatteryThreshold() async throws {
        let process = try RealProcess.app()
        defer { process.cleanup() }
        let assertions = OwnedAssertions(pid: process.pid)
        try eventually("assertion registration") { !assertions.currentAssertions().isEmpty }
        let snapshot = try #require(SysctlProcessTable().snapshot(of: process.pid))
        #expect(snapshot.parentPID == getpid())
        #expect(!snapshot.hasControllingTerminal)
        #expect(!ProcessClassifier.shellNames.contains(
            SysctlProcessTable().snapshot(of: getpid())?.name ?? ""
        ))
        #expect(ProcessClassifier().origin(of: process.pid) == .app)

        let fixture = IntegrationFixture(assertions: assertions, process: process)
        defer { fixture.stop() }
        await fixture.engine.start()
        await fixture.time.fire()
        #expect(fixture.notices.contains(.keepAwakeDetected, pid: process.pid))
        #expect(!fixture.notices.contains(.processTerminated, pid: process.pid))
        #expect(kill(process.pid, 0) == 0)
        #expect(fixture.engine.blockers.contains("caffeinate"))

        fixture.power.current = PowerState(source: .battery, batteryPercent: 15, isCharging: false)
        await fixture.time.fire()
        #expect(fixture.notices.contains(.processTerminated, pid: process.pid))
        #expect(kill(process.pid, 0) == -1 && errno == ESRCH)
        try eventually("assertion release") { assertions.currentAssertions().isEmpty }
    }

    @Test func controllerAssertionIsHiddenAndReleasedAtThreshold() async throws {
        let assertions = OwnedAssertions(pid: getpid(), name: CaffeinateController.assertionName)
        let fixture = IntegrationFixture(assertions: assertions)
        defer { fixture.stop() }
        fixture.controller.activate()
        #expect(fixture.controller.isActive)
        try eventually("assertion registration") { !assertions.currentAssertions().isEmpty }
        fixture.controller.deactivate()
        try eventually("assertion release") { assertions.currentAssertions().isEmpty }

        fixture.controller.activate()
        try eventually("assertion registration") { !assertions.currentAssertions().isEmpty }
        await fixture.engine.start()
        #expect(fixture.controller.isActive)
        #expect(fixture.engine.blockers.isEmpty)
        fixture.power.current = PowerState(source: .battery, batteryPercent: 15, isCharging: false)
        await fixture.time.fire()
        #expect(!fixture.controller.isActive)
        try eventually("assertion release") { assertions.currentAssertions().isEmpty }
        #expect(fixture.notices.notices.contains { $0.title == "Keep-awake released" })
    }

    @Test func otherOwnPIDAssertionIsHiddenAndNeverTerminated() async throws {
        let holder = IOKitSleepAssertionHolder()
        let name = "Integration report-only sleep assertion"
        let handle = try #require(holder.create(name: name))
        defer { holder.release(handle) }
        let assertions = OwnedAssertions(pid: getpid(), name: name)
        try eventually("assertion registration") { !assertions.currentAssertions().isEmpty }
        let assertion = try #require(assertions.currentAssertions().first)
        #expect(!assertion.isCaffeinate)
        let fixture = IntegrationFixture(assertions: assertions)
        defer { fixture.stop() }
        await fixture.engine.start()
        fixture.power.current = PowerState(source: .battery, batteryPercent: 15, isCharging: false)
        await fixture.time.fire()
        fixture.power.current = PowerState(source: .battery, batteryPercent: 1, isCharging: false)
        await fixture.time.fire()
        #expect(!fixture.notices.contains(.keepAwakeDetected, pid: getpid()))
        #expect(!fixture.notices.notices.contains { $0.title == "Sleep blocker reported" })
        #expect(!fixture.notices.contains(.processTerminated, pid: getpid()))
        #expect(!fixture.notices.notices.contains { $0.title == "Stopping keep-awake process" })
        #expect(fixture.engine.blockers.isEmpty)
        #expect(!assertions.currentAssertions().isEmpty)
    }
}
