<!--
Copyright 2026 Francisco Perdigon Romero and contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Releasing MacPocketKnife

The app is a pure Swift package. Releases contain a universal Apple silicon and
Intel app for macOS 13 or later in an **ad-hoc signed DMG, not notarized**.
The entire bundle is sealed with an ad-hoc signature. No Apple Developer account,
Developer ID certificate, notarization credentials, or repository secrets are
required. GitHub supplies the workflow token with `contents: write`.

## Branches and versions

`main` is the trunk. Develop on feature branches and merge through pull requests.
`VERSION` holds a numeric `major.minor.patch` version. The
`Resources/Info.plist` template uses `@VERSION@` for both bundle version strings;
the bundle script resolves them from `VERSION`, so there is only one version to
update. Tags must be `v` followed by that exact version.

Use rmount's changelog conventions when recording release changes: Keep a
Changelog sections (`Added`, `Changed`, `Fixed`) under `Unreleased`, then a
Semantic Versioning heading and release date. Published release notes are generated
from commit subjects by `scripts/release-notes.sh`, with a full comparison link
for tagged releases. Use descriptive commit subjects.

## Build and verify locally

Install Xcode and select its command line tools, then run from the repository root:

```sh
swift build
swift test
python3 -m unittest discover -s scripts/tests -v
sh scripts/test-make-app-bundle.sh
BUILD_CHANNEL=dev scripts/build-release.sh
```

The output is `dist/MacPocketKnife-0.1.0.dmg` (using the current `VERSION`)
and its `.sha256` file. The DMG holds `MacPocketKnife.app` and an
Applications shortcut. `scripts/verify-dmg.sh` mounts it read-only, checks bundle
metadata, executable permissions, both architectures and the whole-bundle
signature, then unmounts even if a check fails. It never launches the app.
The Python unit tests use fake disk and signing tools, without mounting images.

The bundle and release scripts forward extra arguments to `swift build`.
When the local sandbox blocks SwiftPM, append `--disable-sandbox` to build/test
commands and bundle/release scripts.

Build metadata for the updater is embedded before sealing:

- `CFBundleShortVersionString` and `CFBundleVersion`: `VERSION`.
- `CAMGitSHA`: full `GITHUB_SHA`, otherwise `git rev-parse HEAD`, or `unknown`
  outside a Git checkout.
- `CAMBuildChannel`: `BUILD_CHANNEL` (`stable`, `nightly`, or `dev`; default `dev`).
  The Release workflow sets `stable` for tags, `nightly` for main, and `dev` for
  other manually selected branches.

CI runs Swift tests with coverage on macOS 14. Pull requests need at least 80%
coverage of changed core source lines through llvm-cov export and diff-cover.
Generated code, tests and the thin `Sources/MacPocketKnife/` UI executable
are excluded, as rmount excludes its `App/` UI. Keep testable logic in
`MacPocketKnifeCore`. The macOS 15 job also compiles the Swift package's app
scheme with the Xcode toolchain and signing disabled.

## Tag and publish

1. Update `VERSION` and merge the version change through a pull request after CI
   passes. The Info.plist template needs no version edit.
2. Tag the intended main revision and push the tag, for example:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. The Release workflow checks the tag, runs tests, builds and verifies the DMG,
   and creates a regular GitHub Release with generated notes and SHA-256 checksums.
   A version mismatch fails before publishing. Tagged releases are ad-hoc signed
   and not notarized, just like nightlies.

## Nightlies and manual runs

Every commit on `main`, including merged PRs and direct pushes, publishes a
`nightly-YYYYMMDD-<sha>` pre-release. Notes identify the date and commit and say:
“Automated build of main ... Unsigned (ad-hoc signed, not notarized) and unstable”.
Assets include the date and short SHA. Re-running the same commit on the same day
skips publication when that release already exists.

The `KEEP_NIGHTLIES` repository Actions variable controls retention (positive
integer, default `1`). After publishing, older nightly releases are removed;
their tags remain. The newest notes carry forward previous nightly history,
limited to 100 KB. When no usable previous nightly exists, changes start at the
latest version tag, or the latest 20 commits. Tagged releases are never pruned.

A manual `workflow_dispatch` follows the selected ref just like a push: tags
publish regular releases, branches publish pre-releases. Select `main` for a
nightly; a different branch embeds the `dev` build channel. No Developer ID or
notarization steps run in any case.

## Verify and install a download

Download a DMG and its matching `.sha256` from the same
[GitHub Release](https://github.com/fperdigon/macpocketknife/releases).
In the download directory, for example:

```sh
shasum -a 256 -c MacPocketKnife-0.1.0.dmg.sha256
```

The checksum file names the DMG it verifies. For nightlies use the matching
nightly checksum filename. This detects corruption; trust depends on obtaining
the checksum from a trusted release. Developers can also run:

```sh
scripts/verify-dmg.sh MacPocketKnife-0.1.0.dmg
```

Open the DMG, drag the app to Applications, and eject the image. On first launch,
use **System Settings > Privacy & Security > Open Anyway**, then confirm Open.
This is expected for an ad-hoc signed app without notarization. Do not disable
Gatekeeper globally.

## Homebrew tap

The `fperdigon/homebrew-tap` repository bumps the cask daily to the newest stable
release, reading the version and SHA-256 from its release asset. To trigger a
bump manually:

```sh
gh workflow run bump.yml -R fperdigon/homebrew-tap
```

Nightlies are never published to the tap.
