# Cursor Operator Distribution

Cursor Operator should produce a DMG before treating Homebrew Cask as a primary install path.

The reason is structural: a Homebrew Cask is an install channel that points to an already-built artifact URL plus its checksum. For a GUI app, that artifact is normally a signed and notarized DMG or ZIP. A Cask without a stable signed/notarized artifact is only a local convenience, not a real public distribution path.

## Recommendation

Ship in this order:

1. Signed and notarized DMG.
2. Homebrew Cask that references that DMG after the DMG is uploaded to a stable release URL.

For non-public testing, an unsigned DMG is useful for validating bundle layout and install ergonomics, but it should not be described as Gatekeeper-ready.

Homebrew Cask details are based on the official [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook). The macOS requirement uses `:tahoe` because Homebrew maps that symbol to macOS 26 in its [MacOSVersion documentation](https://docs.brew.sh/rubydoc/MacOSVersion.html).

## Build a DMG

From `cursor_operator/`:

```bash
./script/package_distribution.sh dmg
```

Outputs:

- `dist/release/CursorOperator-<version>.dmg`
- `dist/release/CursorOperator-<version>.dmg.sha256`

The DMG contains `CursorOperator.app` plus bundled agent support files:

- `Contents/Library/Helpers/cursor-operator-cli`
- `Contents/Frameworks/Sparkle.framework`
- `Contents/Resources/CursorSDKHelper`
- `Contents/Resources/skills/cursor-operator`

Users install the CLI and skills from the app's Settings window. The app links
`cursor-operator` into `~/.local/bin`, copies the SDK helper next to that
symlink, and links the skill into `~/.codex/skills`, `~/.cursor/skills`, and
`~/.claude/skills`.

By default, the script uses the latest `v*` git tag as the app version, falling back to `0.1.0`. Override it explicitly for release builds:

```bash
CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
./script/package_distribution.sh dmg
```

`CURSOR_OPERATOR_VERSION` must be numeric dotted form such as `0.1.0`, because it is written to `CFBundleShortVersionString`.

## Sparkle Auto-Update

Cursor Operator integrates Sparkle 2 through Swift Package Manager.
The app starts Sparkle only when both `SUFeedURL` and `SUPublicEDKey` are present in the app bundle's `Info.plist`.
Local development bundles omit those keys by default, so debug launches do not try to contact an update feed.

Generate the Sparkle EdDSA key pair once from Sparkle's tools:

```bash
swift package resolve
"$(/usr/bin/find .build -path '*/Sparkle/bin/generate_keys' -type f -perm -111 -print -quit)"
```

Keep the private key in the login Keychain.
Use the printed public key when building a release:

```bash
CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
CURSOR_OPERATOR_APPCAST_URL=https://example.com/cursor-operator/appcast.xml \
CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY="<base64-public-key>" \
./script/package_distribution.sh dmg
```

When those variables are set, the build script writes `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUVerifyUpdateBeforeExtraction`, and `SURequireSignedFeed` to the app bundle.
Automatic update checks are enabled by default for configured release builds.
Automatic installation remains disabled by default.

After building the DMG, generate the Sparkle appcast from the release directory:

```bash
CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
CURSOR_OPERATOR_APPCAST_URL=https://example.com/cursor-operator/appcast.xml \
CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY="<base64-public-key>" \
CURSOR_OPERATOR_GENERATE_APPCAST=1 \
./script/package_distribution.sh dmg
```

`CURSOR_OPERATOR_GENERATE_APPCAST=1` runs Sparkle's `generate_appcast` tool against `dist/release`.
Upload the DMG, any generated delta files, and `appcast.xml` to the HTTPS location referenced by `CURSOR_OPERATOR_APPCAST_URL`.
Use the app's `Check for Updates...` menu item to test a manual check from an older installed build.

## Signing

Unsigned DMGs are allowed by the script so local packaging can be tested without Apple Developer credentials. For distribution, provide a Developer ID Application identity:

```bash
CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
CURSOR_OPERATOR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
./script/package_distribution.sh dmg
```

The script signs the app bundle with hardened runtime and verifies the signature. It does not invent or bypass Apple credentials.

## Notarization

Use a stored notarytool keychain profile:

```bash
xcrun notarytool store-credentials cursor-operator-notary \
  --apple-id "developer@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"

CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
CURSOR_OPERATOR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
CURSOR_OPERATOR_NOTARIZE=1 \
CURSOR_OPERATOR_NOTARY_PROFILE=cursor-operator-notary \
./script/package_distribution.sh dmg
```

Or pass credentials through the environment:

```bash
CURSOR_OPERATOR_VERSION=0.1.0 \
CURSOR_OPERATOR_BUILD_NUMBER=42 \
CURSOR_OPERATOR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
CURSOR_OPERATOR_NOTARIZE=1 \
APPLE_ID="developer@example.com" \
APPLE_TEAM_ID="TEAMID1234" \
APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
./script/package_distribution.sh dmg
```

With `CURSOR_OPERATOR_NOTARIZE=1`, the script submits the DMG with `xcrun notarytool`, waits for the result, staples the DMG, and validates the staple.

## Homebrew Cask

After uploading the notarized DMG, render a Cask:

```bash
./script/render_homebrew_cask.sh \
  0.1.0 \
  https://github.com/taishikato/operator/releases/download/cursor-operator-v0.1.0/CursorOperator-0.1.0.dmg \
  "$(cut -d ' ' -f 1 dist/release/CursorOperator-0.1.0.dmg.sha256)"
```

The rendered Cask:

- installs `CursorOperator.app`
- depends on Homebrew `node`
- declares `depends_on macos: ">= :tahoe"` for macOS 26+
- includes caveats for the runtime Node.js 22.13+ requirement

If a release includes separate Intel and Apple Silicon DMGs, render or maintain separate Cask `on_intel` / `on_arm` blocks with their own URLs and checksums.
