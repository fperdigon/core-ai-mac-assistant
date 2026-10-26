# MacPocketKnife user guide

MacPocketKnife is a personal pocket multi-tool for the Mac menu bar. Its first
tool is a battery guard for forgotten `caffeinate` processes and other sleep blockers.

## Availability and installation

The app monitors battery power and sleep blockers from the menu bar. It provides
battery status, Keep awake, Settings, local notifications, optional Telegram
alerts, and in-app updates. Console-started `caffeinate` processes are terminated
immediately; other apps' blockers are reported and handled at the configured
kill threshold.

## Install

Install with Homebrew or manually from a DMG; follow the corresponding steps in
[README.md](../README.md#install) without repeating them here. The app requires
macOS 13 or later on Apple silicon or Intel. Builds are ad-hoc signed and not
notarized.

Source builds require macOS 13 or later and Swift 6:

```sh
swift build
swift test
swift run MacPocketKnife
```

Use the menu bar menu's Quit command to exit.

## Keep-awake toggle

Turn on Keep Awake in the menu bar to prevent idle system sleep. Turn it off to
release the app's assertion. Indefinite operation is the default. Settings lets
you choose a default duration, and the app restores saved Keep awake state on launch.

## External sleep blockers

The app applies these rules:

- Console-started `caffeinate`: terminate it immediately, notify you, and let the
  app take over keep-awake control. Classification requires conservative console
  ancestry evidence; incomplete or unknown ancestry is treated as app-originated.
- `caffeinate` started by another app, or not classifiable: report it, then
  terminate it only at the battery kill threshold while on battery power.
- Other sleep blockers, such as media players: report them, never terminate them.

Only current-user processes are eligible for termination. The default retry
limit is three termination actions per process name in a rolling 60-second
window, preventing a loop if a process repeatedly relaunches.

## Battery alerts and kill threshold

While on battery with a sleep blocker active, the core schedules an initial
alert, immediate escalation when severity increases, and repeated alerts:

| Battery level | Default repeat interval | Severity |
|---|---|---|
| 50% or higher | 10 minutes | Normal |
| Below 50%, at least 20% | 2 minutes | Urgent |
| Below 20% | 1 minute | Critical |

Alerts stop when external power returns or the blocker disappears. The core
also stops scheduling when the battery percentage is unknown.

At or below the default **15% kill threshold**, while on battery, eligible
`caffeinate` processes are terminated and the app releases its own assertion.
Other sleep blockers remain report-only. Settings controls the threshold and
alert levels and intervals. Alerts are delivered through local notifications;
macOS notification authorization must be allowed for them to appear.

## Telegram setup

Telegram alert delivery is optional and configured in Settings. The bot token is
stored in the macOS Keychain.
The intended setup is:

1. Open Settings and enable Telegram delivery.
2. Use an existing bot token, or open Telegram's BotFather and use `/newbot` to
   create a bot. Follow its prompts and keep the resulting token private.
3. Enter the token in Settings and validate the bot.
   Tokens must be stored only in the macOS Keychain.
4. Begin chat discovery, then open a private conversation with the bot and send
   exactly `/start`. Send a new message after discovery begins: the core discards
   the existing backlog. Discovery times out after 60 seconds by default; retry
   and send a fresh `/start` if needed.
5. Choose Send test message and verify receipt before enabling
   routine delivery. The existing core test-message operation is not silent.

**Silent mode:** routine alerts can be sent without sound;
the core channel supports this option. Telegram alerts are intended to respect
the phone's silent and Do Not Disturb settings. Urgency uses frequency and wording;
delivery and sound also depend on Telegram and device settings.

## Updates

Choose **Check for Updates…** in the status menu, or open **Settings > Updates**
and choose **Check now**. Stable releases are the default; select Nightly for
the newest published development build. A development build with no known commit
never reports that it is current on the Nightly channel.

Automatic checking is on by default. It runs at launch at most once every
24 hours, including failed checks; disable it in Settings for manual checks.
**Later** dismisses an offer. **Skip this version** suppresses that release in
background checks; a manual check can still offer it. Changing channels clears
the skipped release.

**Install and relaunch** downloads the DMG with progress, verifies GitHub's
SHA-256 digest if one is published, mounts the image read-only, and checks the
app's bundle identifier and code signature. Installation stages the bundle on
the same volume and atomically replaces it, retaining a backup through validation.
If installation fails, the app reports an error and restores the backup when
replacement has started. The destination folder must be writable.

The app saves and flushes its current keep-awake state before quitting. A helper
waits for exit and reopens the installed app, which restores the saved state and
expiry. Checks use GitHub's public API; installation downloads only the chosen
release asset. There is no telemetry. See [PRIVACY.md](PRIVACY.md).

## Privacy and removal

There is no telemetry. Local operation needs no network. Optional Telegram
delivery shares the bot credential, destination chat ID, and message content
with Telegram. Machine-name inclusion is opt-in and off by default. Keep tokens
and chat IDs out of logs and shared diagnostics. See [PRIVACY.md](PRIVACY.md).

To remove everything:

1. Disable Telegram and Keep Awake if desired, then quit the app and remove the
   installed app or local build products.
2. If setup or core use stored a token, delete the generic-password Keychain item
   with service `macpocketknife` and account `telegramBotToken` in Keychain
   Access. If a custom service was used, remove its corresponding item instead.
3. Remove the app's UserDefaults preferences using the installed app's actual
   preferences domain. Uninstalling alone does not delete preferences or tokens.
4. Revoke the token through BotFather if it should no longer work. Remove the bot
   and Telegram conversation separately if desired; deleting local data does not
   erase messages already delivered to Telegram.
