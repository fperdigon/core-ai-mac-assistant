<!--
Copyright 2026 The Core AI Mac Assistant contributors

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

# Releasing Core AI Mac Assistant

Releases contain a universal macOS app for Apple silicon and Intel, requiring macOS
13 or later. `VERSION` supplies both bundle version strings. No entitlements are
needed: this app uses Hardened Runtime without App Sandbox.

## Apple credentials

An Apple Developer Program membership is required for Developer ID distribution.
In Keychain Access, use Certificate Assistant to request a certificate from a
certificate authority and save the certificate signing request. In the Apple
Developer account's Certificates, Identifiers & Profiles section, create a
**Developer ID Application** certificate using that request. Download and install
it in the same keychain as the private key. Export the certificate and its private
key together as a password-protected `.p12`. Encode that file as base64 for the
repository secret. Keep the private key and export outside the repository.

In App Store Connect, open Users and Access, Integrations, App Store Connect API.
An Account Holder or Admin can enable API access. Create a team API key with the
Developer role (or another role allowed to submit for notarization). Download its
`.p8` private key, available only once. Record its key ID and issuer ID and encode
the private key as base64. Keep all credentials in secure storage.

Set these repository Actions secrets (names only):

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGN_IDENTITY`
- `NOTARY_API_KEY_P8_BASE64`
- `NOTARY_API_KEY_ID`
- `NOTARY_API_ISSUER_ID`

Use the certificate's full Developer ID Application signing identity for
`MACOS_SIGN_IDENTITY`. `KEYCHAIN_PASSWORD` is generated and masked per run; do not
store it as a repository secret. GitHub supplies `GITHUB_TOKEN` automatically.
The workflow grants it `contents: write` to publish the release. Do not put
credential values in workflow files, shell history, logs, or release notes.

## Local bundle and checks

Install Xcode and select its command line tools. From the repository root:

```sh
sh scripts/test-make-app-bundle.sh
swift build
swift test
```

The bundle test builds both architectures, assembles
`build/Core AI Mac Assistant.app`, and verifies its metadata, architectures,
ad-hoc signature, and Hardened Runtime flag. It does not require credentials or
contact Apple's notarization service. Run it again to rebuild the same bundle.
For a local Developer ID build, set `SIGN_IDENTITY` in the environment and run
`sh scripts/make-app-bundle.sh`. The script applies a secure timestamp with a real
identity. The scripts forward optional arguments to Swift build, so
`sh scripts/test-make-app-bundle.sh --disable-sandbox` is available when required
by the local execution environment. Use that flag for manual Swift build/test
commands in the same environment.

## Tag and publish

1. Update `VERSION` to a numeric `major.minor.patch` value, starting at `0.1.0`.
   Merge the version change after CI passes, including the bundle test.
2. Tag that revision with `v` followed by the exact version, then push the tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. Watch the Release workflow. It imports the certificate into a temporary
   keychain, builds and signs, submits a ZIP to Apple's notary service, checks
   acceptance, staples the ticket, and verifies Gatekeeper assessment and the
   stapled ticket. It then creates a fresh ZIP and SHA-256 checksum and publishes
   both in a GitHub Release. Temporary credentials and the keychain are removed
   even when a step fails.

The tag must match `VERSION` or the workflow fails. When any required credential
is absent, signing and notarization steps are skipped with a clear log message.
The workflow still publishes an **unsigned prerelease**, with `-unsigned` in the
asset filename. That app has only an ad-hoc signature and no notarization ticket;
it is intended for local testing. Gatekeeper assessment is expected to fail for
that fallback. With complete credentials, signing or notarization errors fail the
workflow rather than publishing an unsigned fallback.

## Verify a download

Download the ZIP and its matching `.sha256` file from the same release. In the
download directory, for version `0.1.0`:

```sh
shasum -a 256 -c Core-AI-Mac-Assistant-0.1.0.zip.sha256
ditto -x -k Core-AI-Mac-Assistant-0.1.0.zip .
codesign --verify --strict 'Core AI Mac Assistant.app'
codesign --display --verbose=4 'Core AI Mac Assistant.app'
spctl --assess --type execute --verbose 'Core AI Mac Assistant.app'
xcrun stapler validate 'Core AI Mac Assistant.app'
```

Check that the displayed identifier matches
`io.github.fperdigon.core-ai-mac-assistant` and the signing authority and team match
the project's expected Developer ID. The checksum detects download corruption;
its trust depends on obtaining the checksum from a trusted release. For unsigned
prereleases, use the filename with `-unsigned`; only checksum and ad-hoc signature
verification apply. Do not disable Gatekeeper to validate a production release.

## Follow-up: Homebrew cask

A future Homebrew cask can reference the versioned release ZIP and its SHA-256,
install the app bundle, and declare macOS 13 as the minimum. Keep that work
separate until signed and notarized releases are established.
