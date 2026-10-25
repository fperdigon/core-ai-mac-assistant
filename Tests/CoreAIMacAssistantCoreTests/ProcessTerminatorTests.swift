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
import Foundation
import Testing
import CoreAIMacAssistantCore

private final class TerminationSystem: ProcessTableProviding, ProcessSignalling, TerminationWaiting, @unchecked Sendable {
    private let lock = NSLock()
    private var process: ProcessSnapshot?
    private var alive = true
    private var signals: [Int32] = []
    private var waits: [TimeInterval] = []
    private let exitAfterWait: Int?
    private let replacement: ProcessSnapshot?
    private let signalResult: ProcessSignalResult
    private let cancelWait: Bool

    init(
        process: ProcessSnapshot? = ProcessSnapshot(
            pid: 42, parentPID: 1, name: "caffeinate", hasControllingTerminal: false, userID: 42
        ), exitAfterWait: Int? = 1, replacement: ProcessSnapshot? = nil,
        signalResult: ProcessSignalResult = .sent, cancelWait: Bool = false
    ) {
        self.process = process
        self.exitAfterWait = exitAfterWait
        self.replacement = replacement
        self.signalResult = signalResult
        self.cancelWait = cancelWait
    }

    var sentSignals: [Int32] { lock.withLock { signals } }
    var delays: [TimeInterval] { lock.withLock { waits } }
    func snapshot(of pid: Int32) -> ProcessSnapshot? { lock.withLock { process } }
    func isAlive(_ pid: Int32) -> Bool { lock.withLock { alive } }

    func send(_ signal: Int32, to pid: Int32) -> ProcessSignalResult {
        lock.withLock {
            signals.append(signal)
            return signalResult
        }
    }

    func wait(for interval: TimeInterval) async throws {
        try lock.withLock {
            if cancelWait { throw CancellationError() }
            waits.append(interval)
            if waits.count == exitAfterWait { alive = false; process = nil }
            if waits.count == 1, let replacement { process = replacement }
        }
    }

    func terminator() -> SignalProcessTerminator {
        SignalProcessTerminator(processTable: self, signaller: self, waiter: self,
                                ownPID: 99, currentUserID: 42, gracePeriod: 0.25)
    }
}

@Test func terminatorStopsWithTermWhenProcessExits() async {
    let system = TerminationSystem()
    #expect(await system.terminator().terminate(pid: 42, expectedName: "caffeinate") == .terminated)
    #expect(system.sentSignals == [SIGTERM])
    #expect(system.delays == [0.25])
}

@Test func terminatorEscalatesOnlyAfterGraceAndConfirmsExit() async {
    let system = TerminationSystem(exitAfterWait: 2)
    #expect(await system.terminator().terminate(pid: 42, expectedName: "caffeinate") == .terminated)
    #expect(system.sentSignals == [SIGTERM, SIGKILL])
    #expect(system.delays == [0.25, 0.25])
    let stubborn = TerminationSystem(exitAfterWait: nil)
    #expect(await stubborn.terminator().terminate(pid: 42, expectedName: "caffeinate") == .failed)
    #expect(stubborn.sentSignals == [SIGTERM, SIGKILL])
}

@Test(arguments: [Int32.min, -1, 0, 1, 99])
func terminatorRefusesProtectedPIDs(pid: Int32) async {
    let system = TerminationSystem()
    #expect(await system.terminator().terminate(pid: pid, expectedName: "caffeinate") == .failed)
    #expect(system.sentSignals.isEmpty)
}

@Test func terminatorRefusesMissingMismatchedAndForeignProcesses() async {
    let missing = TerminationSystem(process: nil)
    #expect(await missing.terminator().terminate(pid: 42, expectedName: "caffeinate") == .notFound)
    #expect(missing.sentSignals.isEmpty)
    let renamed = TerminationSystem(process: ProcessSnapshot(
        pid: 42, parentPID: 1, name: "ExampleApp", hasControllingTerminal: false, userID: 42
    ))
    #expect(await renamed.terminator().terminate(pid: 42, expectedName: "caffeinate") == .notFound)
    #expect(renamed.sentSignals.isEmpty)
    let foreign = TerminationSystem(process: ProcessSnapshot(
        pid: 42, parentPID: 1, name: "caffeinate", hasControllingTerminal: false, userID: 43
    ))
    #expect(await foreign.terminator().terminate(pid: 42, expectedName: "caffeinate") == .failed)
    #expect(foreign.sentSignals.isEmpty)
}

@Test func terminatorRechecksNameAndOwnerBeforeKill() async {
    let renamed = TerminationSystem(exitAfterWait: nil, replacement: ProcessSnapshot(
        pid: 42, parentPID: 1, name: "ExampleApp", hasControllingTerminal: false, userID: 42
    ))
    #expect(await renamed.terminator().terminate(pid: 42, expectedName: "caffeinate") == .notFound)
    #expect(renamed.sentSignals == [SIGTERM])
    let foreign = TerminationSystem(exitAfterWait: nil, replacement: ProcessSnapshot(
        pid: 42, parentPID: 1, name: "caffeinate", hasControllingTerminal: false, userID: 43
    ))
    #expect(await foreign.terminator().terminate(pid: 42, expectedName: "caffeinate") == .failed)
    #expect(foreign.sentSignals == [SIGTERM])
}

@Test func terminatorHandlesSignalFailuresAndCancellationWithoutEscalating() async {
    let denied = TerminationSystem(signalResult: .failed)
    #expect(await denied.terminator().terminate(pid: 42, expectedName: "caffeinate") == .failed)
    #expect(denied.sentSignals == [SIGTERM])
    #expect(denied.delays.isEmpty)
    let gone = TerminationSystem(signalResult: .notFound)
    #expect(await gone.terminator().terminate(pid: 42, expectedName: "caffeinate") == .notFound)
    let cancelled = TerminationSystem(cancelWait: true)
    #expect(await cancelled.terminator().terminate(pid: 42, expectedName: "caffeinate") == .failed)
    #expect(cancelled.sentSignals == [SIGTERM])
}
