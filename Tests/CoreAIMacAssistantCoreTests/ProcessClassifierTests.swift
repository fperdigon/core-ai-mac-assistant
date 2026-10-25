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

private func process(
    _ pid: Int32, parent: Int32, name: String, terminal: Bool = false
) -> ProcessSnapshot {
    ProcessSnapshot(pid: pid, parentPID: parent, name: name, hasControllingTerminal: terminal)
}

@Test func caffeinateFromZshInsideTerminalIsConsole() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate", terminal: true),
        process(41, parent: 40, name: "zsh", terminal: true),
        process(40, parent: 1, name: "Terminal"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .console)
}

@Test(arguments: [
    "Terminal", "iTerm2", "ghostty", "kitty", "alacritty", "WezTerm", "wezterm-gui",
    "Warp", "tmux", "tmux: server", "screen", "sshd", "login", "Hyper",
]) func terminalOrRemoteAncestorProvidesEvidence(name: String) {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate"),
        process(41, parent: 40, name: "zsh"),
        process(40, parent: 1, name: name),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .console)
}

@Test(arguments: ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "nu"])
func shellWithControllingTerminalIsConsole(name: String) {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate"),
        process(41, parent: 1, name: name, terminal: true),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .console)
}

@Test func processControllingTerminalProvidesEvidenceForShellAncestor() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate", terminal: true),
        process(41, parent: 1, name: "zsh"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .console)
}

@Test func guiAppDirectLaunchIsApp() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate"),
        process(41, parent: 1, name: "ExampleApp"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test(arguments: ["ExampleApp", "Code Helper"])
func guiAppShellWithoutTerminalIsApp(name: String) {
    // sh -c is represented by its process name, without its command arguments.
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate"),
        process(41, parent: 40, name: "sh"),
        process(40, parent: 1, name: name),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func terminalAncestorWithoutShellIsApp() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate", terminal: true),
        process(41, parent: 1, name: "Terminal"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func unrelatedAncestorTerminalDoesNotProvideControllingTerminalEvidence() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate"),
        process(41, parent: 40, name: "sh"),
        process(40, parent: 1, name: "ExampleApp", terminal: true),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func shellItselfDoesNotCountAsShellAncestor() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "zsh", terminal: true),
        process(41, parent: 1, name: "Terminal"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func brokenChainAfterConsoleEvidenceIsApp() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate", terminal: true),
        process(41, parent: 40, name: "zsh"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func missingProcessIsApp() {
    #expect(ProcessClassifier(processTable: FakeProcessTable()).origin(of: 42) == .app)
}

@Test func parentCycleAfterConsoleEvidenceIsApp() {
    let table = FakeProcessTable([
        process(42, parent: 41, name: "caffeinate", terminal: true),
        process(41, parent: 40, name: "zsh"),
        process(40, parent: 41, name: "Terminal"),
    ])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func processParentedToItselfIsApp() {
    let table = FakeProcessTable([process(42, parent: 42, name: "caffeinate", terminal: true)])
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test(arguments: [12, 13]) func depthLimitRequiresCompleteChain(count: Int) {
    let snapshots = (0..<count).map { index in
        process(
            Int32(100 + index),
            parent: index == count - 1 ? 1 : Int32(101 + index),
            name: index == 1 ? "zsh" : "caffeinate",
            terminal: index == 0
        )
    }
    let classifier = ProcessClassifier(processTable: FakeProcessTable(snapshots))
    #expect(classifier.origin(of: 100) == (count == 12 ? .console : .app))
}

@Test func shellBeyondDepthLimitIsApp() {
    var snapshots: [ProcessSnapshot] = []
    for index in 0..<13 {
        let pid = Int32(100 + index)
        let parent: Int32 = index == 12 ? 1 : pid + 1
        let name = index == 12 ? "zsh" : "caffeinate"
        snapshots.append(process(pid, parent: parent, name: name, terminal: true))
    }
    #expect(ProcessClassifier(processTable: FakeProcessTable(snapshots)).origin(of: 100) == .app)
}

@Test(arguments: [Int32(-1), 0, 1]) func systemPIDsAreApp(pid: Int32) {
    #expect(ProcessClassifier(processTable: FakeProcessTable()).origin(of: pid) == .app)
}

@Test func mismatchedSnapshotIsApp() {
    var table = FakeProcessTable()
    table.snapshots[42] = process(43, parent: 1, name: "zsh", terminal: true)
    #expect(ProcessClassifier(processTable: table).origin(of: 42) == .app)
}

@Test func sysctlProcessClassifierDoesNotCrash() {
    // Smoke coverage only: the result must not depend on the test runner's ancestry.
    _ = ProcessClassifier(processTable: SysctlProcessTable()).origin(of: getpid())
}
