# Core AI Mac Assistant

A native macOS menu bar app being built to protect the battery from forgotten
`caffeinate` processes and other sleep blockers. It is designed for offline use
with local alerts and an optional Telegram channel.

## Status

The menu bar app currently displays the project title and a Quit command.
The Settings UI and wiring are in progress. Automatic protection, local
notifications, and Telegram controls are **planned** in the app.

Implemented core components include:

- IOKit power monitoring and sleep assertion discovery, with parsers.
- Process ancestry classification and a pure policy engine with ownership and
  termination retry limits; the engine returns actions for a caller to execute.
- Keep-awake assertion control, optional expiry, and local state restoration.
- Battery alert scheduling and configurable thresholds.
- Telegram client, token validation, fresh `/start` chat discovery, test message,
  alert formatting, and silent delivery support.
- Keychain secret storage and sensitive-text redaction.

These components have tests but are not yet connected to the menu bar app.
Running the app today does not monitor or terminate processes or send alerts.

## Protection rules

The rules from [the project plan](docs/PLAN.md) describe the intended app behavior.
The core policy exists; executing its actions in the app is planned.

| Origin | Behavior |
|---|---|
| Started from a console (shell, Terminal, iTerm, tmux or ssh in the parent chain) | Terminated immediately; the user is told. The app takes over. |
| Started by another app, or not classifiable | Only reported. Terminated when the battery reaches the kill threshold (default 15%) on battery power. |
| The app's own assertion | Indefinite by default. Released at the kill threshold like the others. |
| Other sleep blockers (media players, other keep-awake tools) | Reported only, never terminated. |

Only processes owned by the current user are eligible for termination. A retry
limit prevents repeated termination if something keeps relaunching `caffeinate`.
Console classification uses conservative ancestry heuristics; incomplete evidence
is treated as app-originated.

## Build, test, and run from source

Requires macOS 13 or later and a Swift 6 toolchain. There are no external package
dependencies. From the repository root:

```sh
swift build
swift test
swift run CoreAIMacAssistant
```

The app runs in the menu bar without a Dock icon. Use its menu to quit.
See [CONTRIBUTING.md](CONTRIBUTING.md) for repository checks and testing guidance,
and the [user guide](docs/USER_GUIDE.md) for planned controls and setup.

## Privacy

No telemetry, analytics, advertising, or remote crash reporting. The optional
Telegram channel is the only intended network use. Its bot token belongs in the
macOS Keychain; nonsecret preferences stay local. Machine-name inclusion is
opt-in and disabled by default in the core formatter.

See [privacy and removal details](docs/PRIVACY.md). Report vulnerabilities using
the private process in [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
