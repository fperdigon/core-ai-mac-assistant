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

public enum ProcessTerminationResult: Sendable, Equatable {
    case terminated
    case notFound
    case failed
}

public protocol ProcessTerminating: Sendable {
    func terminate(pid: Int32, expectedName: String) async -> ProcessTerminationResult
}

public enum ProcessSignalResult: Sendable {
    case sent
    case notFound
    case failed
}

public protocol ProcessSignalling: Sendable {
    func send(_ signal: Int32, to pid: Int32) -> ProcessSignalResult
    func isAlive(_ pid: Int32) -> Bool
}

public struct SystemProcessSignaller: ProcessSignalling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> ProcessSignalResult {
        if kill(pid, signal) == 0 { return .sent }
        return errno == ESRCH ? .notFound : .failed
    }

    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

public protocol TerminationWaiting: Sendable {
    func wait(for interval: TimeInterval) async throws
}

public struct TerminationWaiter: TerminationWaiting {
    public init() {}

    public func wait(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(interval))
    }
}

public struct SignalProcessTerminator: ProcessTerminating {
    private let processTable: any ProcessTableProviding
    private let signaller: any ProcessSignalling
    private let waiter: any TerminationWaiting
    private let ownPID: Int32
    private let currentUserID: UInt32
    private let gracePeriod: TimeInterval

    public init(
        processTable: any ProcessTableProviding = SysctlProcessTable(),
        signaller: any ProcessSignalling = SystemProcessSignaller(),
        waiter: any TerminationWaiting = TerminationWaiter(),
        ownPID: Int32 = getpid(), currentUserID: UInt32 = getuid(),
        gracePeriod: TimeInterval = 0.5
    ) {
        self.processTable = processTable
        self.signaller = signaller
        self.waiter = waiter
        self.ownPID = ownPID
        self.currentUserID = currentUserID
        self.gracePeriod = gracePeriod.isFinite ? max(0, gracePeriod) : 0.5
    }

    public func terminate(pid: Int32, expectedName: String) async -> ProcessTerminationResult {
        guard pid > 1, pid != ownPID, !expectedName.isEmpty else { return .failed }
        for signal in [SIGTERM, SIGKILL] {
            guard !Task.isCancelled else { return .failed }
            // Never carry a process name or ownership decision across the grace period.
            guard let snapshot = processTable.snapshot(of: pid) else {
                return signal == SIGTERM ? .notFound : .terminated
            }
            guard snapshot.pid == pid, snapshot.name == expectedName else { return .notFound }
            guard snapshot.userID == currentUserID else { return .failed }
            switch signaller.send(signal, to: pid) {
            case .notFound: return signal == SIGTERM ? .notFound : .terminated
            case .failed: return .failed
            case .sent: break
            }
            do { try await waiter.wait(for: gracePeriod) } catch { return .failed }
            if !signaller.isAlive(pid) { return .terminated }
        }
        return .failed
    }
}
