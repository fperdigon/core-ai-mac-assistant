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

public struct ProcessClassifier: Sendable {
    /// Exact process names of shells that can establish console ancestry.
    public static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "nu",
    ]

    /// Terminal emulators, multiplexers, and remote login entry processes.
    /// Code Helper is deliberately excluded: editor subprocesses alone are not console evidence.
    public static let terminalNames: Set<String> = [
        "Terminal", "iTerm2", "ghostty", "kitty", "alacritty", "WezTerm", "wezterm-gui",
        "Warp", "tmux", "tmux: server", "screen", "sshd", "login", "Hyper",
    ]

    /// Maximum number of snapshots, including the process being classified.
    public static let maximumDepth = 12

    private let processTable: any ProcessTableProviding

    public init(processTable: any ProcessTableProviding = SysctlProcessTable()) {
        self.processTable = processTable
    }

    public func isOwnedByCurrentUser(_ pid: Int32, currentUserID: UInt32) -> Bool {
        guard let snapshot = processTable.snapshot(of: pid), snapshot.pid == pid else {
            return false
        }
        return snapshot.userID == currentUserID
    }

    public func origin(of pid: Int32) -> ProcessOrigin {
        var currentPID = pid
        var visited: Set<Int32> = []
        var hasShellAncestor = false
        var hasTerminalEvidence = false

        for depth in 0..<Self.maximumDepth {
            if currentPID <= 1 {
                return hasShellAncestor && hasTerminalEvidence ? .console : .app
            }
            guard visited.insert(currentPID).inserted,
                  let snapshot = processTable.snapshot(of: currentPID),
                  snapshot.pid == currentPID else {
                return .app
            }

            let isShellAncestor = depth > 0 && Self.shellNames.contains(snapshot.name)
            hasShellAncestor = hasShellAncestor || isShellAncestor
            if (depth == 0 || isShellAncestor) && snapshot.hasControllingTerminal {
                hasTerminalEvidence = true
            }
            if depth > 0 && Self.terminalNames.contains(snapshot.name) {
                hasTerminalEvidence = true
            }
            currentPID = snapshot.parentPID
        }

        // Only a complete chain is safe to classify as console-originated.
        guard currentPID <= 1 else { return .app }
        return hasShellAncestor && hasTerminalEvidence ? .console : .app
    }
}
