# Core AI Mac Assistant: Plan

A native macOS menu bar app that watches for situations where the user is likely to make a mistake and warns them. The first feature is protecting the battery from a forgotten `caffeinate`.

Name: *Core AI Mac Assistant* (decided in #14; the name stays as is).

## Problem

`caffeinate` (or any sleep-blocking app) is often left running. After unplugging the charger the Mac never sleeps and the battery drains to zero without the user noticing.

## Goals

- Replace `caffeinate` with an app-controlled toggle, and keep control of the sleep state in one place.
- Detect sleep assertions created elsewhere and act on them according to clear rules.
- Warn the user with escalating alerts while on battery.
- Work fully offline with local notifications; Telegram is an optional extra channel.
- Be safe to distribute as free software: no personal data in the repository, secrets only in the Keychain.

## Non-goals

- No notifications on the login screen or to other users' sessions (macOS does not allow normal notifications there).
- No telemetry.
- No Mac App Store distribution (the sandbox prevents terminating other processes).

## Architecture

Swift package, menu bar app (same style as `macsh`). Modules are kept small and testable:

| Module | Responsibility |
|---|---|
| `PowerMonitor` | Power source and battery level events via IOKit (no polling). |
| `AssertionMonitor` | Lists sleep assertions and the processes that own them. |
| `CaffeinateController` | The app's own sleep assertion; indefinite by default; state restored on launch. |
| `ProcessClassifier` | Decides whether a process was started from a console or by another app. |
| `Policy` | Pure decision logic: what to do for a given power state and set of assertions. |
| `Notifier` | Local notifications (level 0) and optional Telegram. |
| `Settings` / `Secrets` | Preferences on disk; secrets in the Keychain. |

`Policy` has no side effects, so the rules below are covered by unit tests.

### AssistantEngine

`AssistantEngine` runs on the main actor and evaluates power changes and periodic
10-second assertion snapshots. It classifies ownership and origin, applies the
stateful policy, executes guarded process termination or releases its own assertion,
and schedules battery alerts for the remaining blockers. Settings are read on every
evaluation without resetting detection, retry history, or alert cadence. Protocols
isolate clocks, ticks, providers, signals, and notification channels for deterministic
tests. Local and optional Telegram delivery fan out independently; the app target
only constructs adapters and presents engine and controller state in the menu.

## Caffeinate rules

| Origin | Behavior |
|---|---|
| Started from a console (shell, Terminal, iTerm, tmux or ssh in the parent chain) | Terminated immediately; the user is told. The app takes over. |
| Started by another app, or not classifiable | Only reported. Terminated when the battery reaches the kill threshold (default 15%) on battery power. |
| The app's own assertion | Indefinite by default. Released at the kill threshold like the others. |
| Other sleep blockers (media players, other keep-awake tools) | Reported only, never terminated. |

Only processes owned by the current user can be terminated. A retry limit prevents a kill loop if something keeps relaunching `caffeinate`.

## Alerts on battery

Thresholds are configurable. Defaults:

| Battery | Frequency | Kind |
|---|---|---|
| 100% to 50% | every 10 minutes | normal |
| below 50% | every 2 minutes | urgent |
| below 20% | every 1 minute | urgent, loudest sound |
| at the kill threshold | once, before and after the action | action notice |

Alerts stop as soon as the charger is connected or the blocking assertion is gone.

## Channels

1. **Local notification (level 0).** Always on, delivered to the active session.
2. **Telegram (optional).** Configured inside the app:
   - Use an existing bot token, or follow a guided flow to create one with BotFather.
   - Discover the chat ID automatically after the user sends `/start` to the bot.
   - "Send test message" button.
   - Messages respect the phone's silent and Do Not Disturb settings. Urgency is conveyed by frequency and wording only. An optional silent mode sends without sound.

## Privacy and secrets

- Bot token only in the macOS Keychain; never in config files, logs or the repository.
- No personal identifiers, hostnames or paths in code, examples or test fixtures.
- Messages contain the minimum (battery level, what is blocking sleep). Including the Mac's name is opt-in.
- The only network access is to the Telegram API, and only when enabled.
- Secret scanning runs in CI.

## Quality

- Unit tests for `Policy`, `ProcessClassifier` and message formatting; protocol-based fakes for IOKit, process tables, Keychain and the Telegram client.
- CI builds and tests on every pull request.
- All code, comments, documentation and issues are written in English.

## Distribution and license

- Apache-2.0 (`LICENSE`, `NOTICE`, source headers).
- Ad-hoc signed DMGs, not notarized, published on GitHub Releases. Homebrew cask is a possible follow-up.

## Working method

Coding tasks are delegated to the Codex CLI as much as possible to save tokens; Claude plans, reviews diffs and runs tests.

## Open questions

- How to keep the "started from a console" detection reliable across terminals as new terminal apps appear (the current rule combines the parent chain with a controlling TTY; see `ProcessClassifier`).
