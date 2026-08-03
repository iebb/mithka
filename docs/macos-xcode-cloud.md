# macOS Xcode Cloud and TestFlight

Xcode Cloud is Mithka's only macOS TestFlight delivery path. A validated
`master` commit is fast-forwarded to `release-ios`; the macOS Xcode Cloud
workflow archives that exact revision and distributes it to the external
TestFlight group. There is no GitHub Actions TestFlight uploader, avoiding
duplicate build numbers and permanently internal-only builds.

The archive uses the version in `pubspec.yaml`, Flutter 3.44.2, Xcode Cloud's
monotonically increasing build number, and a checksum-pinned universal TDLib
artifact.

## Repository-side setup

Xcode Cloud automatically runs `ci_scripts/ci_post_clone.sh`. The dispatcher preserves the existing iOS setup and selects `ci_scripts/macos_post_clone.sh` when the macOS workflow sets `MITHKA_CI_PLATFORM` to `macos`.

The macOS helper:

1. Installs the pinned Flutter SDK and CocoaPods when necessary.
2. Writes `lib/config/secrets.dart` without logging secret values.
3. Downloads the pinned `tdjson-macos-universal.zip`, verifies both the archive
   and dylib SHA-256 checksums, architectures, patched exports, install name,
   and portable dependencies.
4. Generates the release Flutter/Xcode configuration.
5. Restores the CocoaPods sandbox used by desktop-only plugins.

The published artifact is:

- Release: `tdlib-1.8.66-1b08c83bc078-rebuild-29623073124-1`
- Asset: `tdjson-macos-universal.zip`
- Archive SHA-256: `9520190747fe1f855d8445996cf92f1a57fca303a15cd3ec7c0849d9a49aaabc`
- Dylib SHA-256: `d543b42be66306dded64b55b980ec8cf88ae1d43bebf019cc3fa0ca4bb7e5482`

## Xcode Cloud workflow

Use these settings:

- Repository branch: `release-ios`.
- Project or workspace: `macos/Runner.xcworkspace`.
- Scheme: `Runner`.
- Platform and destination: macOS, Any Mac.
- Action: Archive using the Release configuration.
- Xcode and macOS: a stable image compatible with Flutter 3.44.2; avoid beta images.
- Distribution audience: App Store eligible; do not mark the build
  internal-only.

After App Store Connect finishes processing the exact macOS build, add it to
the external group named `External`, populate its localized What to Test text,
and submit it for Beta App Review when required. Xcode Cloud creates an
external-capable build but does not assign it to tester groups automatically.

Before the first distribution, open App Store Connect → Xcode Cloud → Settings
→ Build Number and set **Next Build Number** to an integer greater than every
macOS build already uploaded for Mithka. Xcode Cloud starts at `1` by default,
but macOS build numbers must increase across app versions.

Add these workflow environment variables and mark both as secret:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

Also add `MITHKA_CI_PLATFORM` with the non-secret value `macos`. `SENTRY_DSN`
is optional and should be secret when configured. Xcode Cloud manages the
signing certificate and provisioning profile; no App Store Connect private key
is stored in GitHub for this workflow.

The prebuilt TDLib download makes a cold Xcode Cloud archive independent of the
GitHub Actions cache and avoids the long universal source compilation step.

## App Store metadata prerequisite

The macOS target currently uses a temporary App Sandbox exception for interactive screen capture. Before App Review, App Store Connect must include App Sandbox Entitlement Usage Information that identifies the entitlement, explains how reviewers can exercise it, why it is required, and the related Feedback Assistant issue ID. TestFlight upload alone does not complete this review metadata.
