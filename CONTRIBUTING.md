# Contributing

Use English for code, comments, documentation, issues, and pull requests.
Keep changes focused on one issue and explain the resulting behavior.

## Build and test

Use macOS 13 or later with a Swift 6 toolchain. No external dependencies are
required. Run these commands from the repository root:

```sh
swift build
swift test
sh scripts/check-license-headers.sh
sh scripts/test-check-license-headers.sh
sh scripts/scan-secrets.sh
sh scripts/test-scan-secrets.sh
```

If the environment blocks SwiftPM's build sandbox, use `--disable-sandbox` with
`swift build` and `swift test`. The existing Keychain integration test is skipped
when `CI` is set; use `CI=1 swift test` to avoid accessing the real Keychain.

Run `swift run MacPocketKnife --print-status` to print the current status line once and exit.
Run `swift run MacPocketKnife --show-settings` to open Settings immediately after launch.
Run `swift run MacPocketKnife --snapshot-settings <directory>` to save PNG snapshots of every Settings tab and exit.

## macOS integration tests

`MacPocketKnifeIntegrationTests` runs real caffeinate processes, pseudo-terminal
shells, and IOKit sleep assertions with fake battery state and policy time. Run it
with `swift test --filter MacPocketKnifeIntegrationTests` (or as part of
`swift test`). It needs no display or network. The suite skips when `forkpty` or
pseudo-terminals are unavailable; the direct-spawn scenario additionally requires
a runner without a controlling terminal, as on macOS CI. Each test scopes assertion
listings to its own processes and tears down its children and sleep assertions.
Bounded OS-readiness polling does not drive policy time.

## Speech tests

Run `scripts/run-speech-test.sh` to feed the synthetic clips in
`Tests/Fixtures/Speech` to Apple's on-device recognizer and check the transcripts.
The first run shows the macOS Speech Recognition prompt once. The Spanish case needs
offline Spanish dictation (System Settings > Keyboard > Dictation); without it the
case is skipped with a hint. In CI only English runs, because the runner has no
offline Spanish model. The test exercises the recognizer on synthetic audio and does
not cover the microphone, hotkey or clipboard path.

## Code style and tests

Follow nearby sources: four-space indentation, Swift naming conventions,
small types, and the existing Apache-2.0 copyright and license header at the
start of every Swift source and test file. Keep Swift 6 concurrency checks clean;
use `Sendable` and main-actor isolation where appropriate.

Add Swift Testing tests (`import Testing`) for new or changed logic. Put pure
logic behind protocols where it needs external inputs, and inject fakes for
power, process tables, assertions, storage, networking, and time. New logic tests
must not depend on real hardware state, the network, or the real clock.

Do not commit personal data, identifiers, hostnames, local filesystem locations,
bot tokens, or other secrets, including in fixtures, logs, and screenshots.
Use neutral synthetic examples. Never allowlist a real credential.

## Reporting issues

Open a GitHub issue with a short description, expected and actual behavior,
reproduction steps, macOS and Swift versions, and the relevant app version or
revision. Remove sensitive information from any diagnostics before sharing.
Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Contributions are licensed under Apache-2.0; preserve [LICENSE](LICENSE),
[NOTICE](NOTICE), and source headers.
