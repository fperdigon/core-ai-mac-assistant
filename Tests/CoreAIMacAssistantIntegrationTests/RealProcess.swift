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
import CoreAIMacAssistantCore

enum IntegrationFailure: Error {
    case systemCall(String, Int32)
    case readinessTimeout(String)
}

/// Policy time is fake. This bounded polling only synchronizes external OS effects.
func eventually(_ description: String = "OS readiness", _ condition: () -> Bool) throws {
    for _ in 0..<500 {
        if condition() { return }
        usleep(10_000)
    }
    throw IntegrationFailure.readinessTimeout(description)
}

final class RealProcess: @unchecked Sendable {
    static let ptyAvailable: Bool = {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard dlsym(UnsafeMutableRawPointer(bitPattern: -2), "forkpty") != nil,
              openpty(&master, &slave, nil, nil, nil) == 0 else { return false }
        close(master)
        close(slave)
        return true
    }()

    // A direct posix_spawn inherits the runner's session. CI has no controlling TTY.
    static let runnerHasNoTerminal = SysctlProcessTable().snapshot(of: getpid())?
        .hasControllingTerminal == false

    // PID is set during construction, before sharing. Reaping and teardown use the lock.
    private let lock = NSLock()
    private let child: pid_t
    private var reaped = false
    private var master: Int32 = -1
    private(set) var pid: pid_t
    let console: Bool

    private init(child: pid_t, master: Int32 = -1, console: Bool) {
        self.child = child
        pid = child
        self.master = master
        self.console = console
    }

    static func app() throws -> RealProcess {
        let arguments = ["/usr/bin/caffeinate", "-i", "-t", "60"].map { $0.withCString { strdup($0)! } }
        defer { arguments.forEach { free($0) } }
        var argv = arguments.map { Optional($0) } + [nil]
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], nil, nil, &argv, &environment)
        guard status == 0 else { throw IntegrationFailure.systemCall("posix_spawn", status) }
        return RealProcess(child: pid, console: false)
    }

    static func shell() throws -> RealProcess {
        // Keep zsh alive as the parent and let it reap caffeinate, including on teardown.
        // The trap is installed before launch; no shell startup files or user environment.
        let script = """
        unsetopt bgnice
        trap 'child=$!; if (( child > 0 )); then kill -KILL $child 2>/dev/null; wait $child; fi; exit' TERM HUP
        /usr/bin/caffeinate -i -t 60 &
        child=$!
        print -r -- $child
        wait $child
        """
        let arguments = ["/bin/zsh", "-f", "-c", script].map { $0.withCString { strdup($0)! } }
        defer { arguments.forEach { free($0) } }
        var argv = arguments.map { Optional($0) } + [nil]
        var master: Int32 = -1
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        // Prepare all pointers before fork. The child only calls execve/_exit.
        let child = argv.withUnsafeMutableBufferPointer { buffer -> pid_t in
            environment.withUnsafeMutableBufferPointer { environment in
                let executable = UnsafePointer(buffer[0]!)
                let arguments = buffer.baseAddress!
                let variables = environment.baseAddress!
                let child = forkpty(&master, nil, nil, nil)
                if child == 0 {
                    execve(executable, arguments, variables)
                    _exit(127)
                }
                return child
            }
        }
        guard child > 0 else { throw IntegrationFailure.systemCall("forkpty", errno) }
        let process = RealProcess(child: child, master: master, console: true)
        do {
            guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else {
                throw IntegrationFailure.systemCall("fcntl", errno)
            }
            var output = ""
            try eventually("shell PID handshake") {
                var buffer = [UInt8](repeating: 0, count: 256)
                let count = read(master, &buffer, buffer.count)
                if count > 0 { output += String(decoding: buffer.prefix(count), as: UTF8.self) }
                guard output.utf8.contains(10),
                      let line = output.split(whereSeparator: { $0.isNewline }).first,
                      let pid = Int32(line),
                      pid > 1 else { return false }
                process.pid = pid
                return true
            }
            return process
        } catch {
            process.cleanup()
            throw error
        }
    }

    /// Direct children must be reaped before kill(pid, 0) observes them as gone.
    func collectIfExited() {
        lock.withLock {
            guard !reaped else { return }
            var status: Int32 = 0
            let result = waitpid(child, &status, WNOHANG)
            if result == child || (result == -1 && errno == ECHILD) { reaped = true }
        }
    }

    func cleanup() {
        lock.withLock {
            guard !reaped else {
                if master >= 0 { close(master); master = -1 }
                return
            }
            if console {
                // Signal the shell: its trap kills and waits for its child before exiting.
                kill(child, SIGTERM)
            } else {
                kill(child, SIGKILL)
            }
            var status: Int32 = 0
            while waitpid(child, &status, 0) == -1 && errno == EINTR {}
            reaped = true
            if master >= 0 { close(master); master = -1 }
        }
    }

    deinit { cleanup() }
}

struct ProcessExitWaiter: TerminationWaiting {
    let process: RealProcess?

    func wait(for interval: TimeInterval) async throws {
        try eventually {
            process?.collectIfExited()
            guard let process else { return true }
            return kill(process.pid, 0) == -1 && errno == ESRCH
        }
    }
}

/// Scope the real listing before policy execution so unrelated processes are never acted on.
struct OwnedAssertions: AssertionProviding {
    let pid: Int32
    var name: String? = nil

    func currentAssertions() -> [SleepAssertion] {
        IOKitAssertionProvider().currentAssertions().filter {
            $0.pid == pid && (name == nil || $0.name == name)
        }
    }
}
