# Privacy and secrets

Core AI Mac Assistant is designed to work offline with local notifications.
There is no telemetry, analytics, advertising, or remote crash reporting.

## Local storage

The Telegram bot token belongs only in the macOS Keychain, as a generic-password
item with service `core-ai-mac-assistant` and account `telegramBotToken`.
The core Keychain store uses `WhenUnlockedThisDeviceOnly` accessibility and
explicitly disables iCloud synchronization. A custom service can be supplied
by a caller. The token must never be saved in preferences, logs, or source files.

Nonsecret preferences, such as keep-awake state and its optional expiry time,
are stored locally in the app's UserDefaults domain. Alert thresholds and
notification choices are preferences, not secrets. Treat the Telegram chat ID
as private routing information; never put it in source code or logs.

The secret store and redactor are core building blocks. This issue does not
add Telegram networking or settings controls to the menu bar app.
Callers must pass known secret values to `Redactor.redact(_:secrets:)` before
logging or displaying errors that might contain them. It also masks Telegram
bot token patterns and credentials using the `Bearer` authorization scheme.
Redaction is a safeguard, not a reason to log request bodies or credentials.

## Network access and messages

The only intended network destination is the Telegram API, and only when the
optional Telegram channel is enabled. Telegram receives the bot credential,
the destination chat ID, and the message content needed to deliver alerts.
Local notifications require no network access.

Messages contain the battery level and minimal information about what is
blocking sleep or what action was taken. They must not contain credentials,
personal identifiers, filesystem locations, or command arguments. Including
the Mac's name is opt-in and is disabled by default. Telegram processes and
retains delivered messages according to its own policies.

## Removing everything

1. Disable Telegram delivery and quit the app.
2. In Keychain Access, find the generic-password item for the service above and
   delete its `telegramBotToken` entry. For a custom service, delete the item
   under that service instead. Core callers can also use
   `SecretStore.removeSecret(for: .telegramBotToken)`.
3. Remove the app's UserDefaults preferences using the domain of the installed
   app, and remove the app itself. Uninstalling alone does not delete Keychain
   items or preferences.
4. Revoke the bot token through BotFather if it should no longer be usable.
   Delete the Telegram conversation and bot separately if desired; deleting
   local data does not remove messages already delivered to Telegram.

## Repository checks

Run `sh scripts/scan-secrets.sh` from the repository to scan tracked working-tree
files. It detects Telegram bot token patterns, authorization credentials, and
private key headers, and fails without printing matched values. Untracked
files and Git history are outside its scope. Only the scanner itself is
excluded. A fake placeholder is accepted only if its complete matched value
is explicitly listed in `scripts/secret-allowlist.txt`; entries are literal,
case-sensitive values, not patterns. Never allowlist a real credential.

Run `sh scripts/test-scan-secrets.sh` to verify rejection of a fake token built
at runtime, along with authorization credentials and private key headers.
The test creates and removes an isolated temporary Git repository.

Run `swift test` for the core tests. The Keychain integration test uses a unique
random service and deletes its item afterward; it is skipped whenever the `CI`
environment variable is set. All other secret store and redactor tests use
in-memory data and require no hardware, network, or real clock.
