# Apple GitHub Actions and TestFlight

Mithka's iOS and macOS TestFlight delivery runs on GitHub Actions. The former
Xcode Cloud workflows remain in App Store Connect in a deactivated state for
rollback and configuration history.

`.github/workflows/macos-testflight.yml` starts for:

- branches beginning with `nightly`;
- the exact `release` branch;
- branches beginning with `release-macos`;
- an explicit manual dispatch.

Those start conditions mirror the former macOS Xcode Cloud workflow. Runs for
the same branch auto-cancel when a newer revision is pushed. A successful run
archives `macos/Runner.xcworkspace`, uploads an App Store-eligible macOS build,
and assigns the processed build to both `Internal` and `External` TestFlight
groups. The former macOS Xcode Cloud workflow is retained in App Store Connect
in a deactivated state for rollback and configuration history.

`.github/workflows/ios-testflight.yml` starts for:

- branches beginning with `nightly`;
- the exact `release` branch;
- branches beginning with `release-ios`;
- an explicit manual dispatch.

Those conditions mirror the former iOS Xcode Cloud workflow. It prepares the
same pinned native dependencies as Xcode Cloud, archives
`ios/Runner.xcworkspace`, verifies that the TDLib binary and dSYM UUIDs match,
and uploads the archive through Xcode's App Store Connect destination so Apple
performs the authoritative distribution validation, and assigns the processed
build to the same Internal and External TestFlight groups.

## Deterministic build preparation

The action uses Flutter 3.44.2 and delegates source preparation to
`ci_scripts/macos_post_clone.sh`. The helper:

1. writes `lib/config/secrets.dart` without logging its values;
2. downloads the checksum-pinned universal TDLib artifact;
3. generates the release Flutter/Xcode configuration;
4. restores the committed CocoaPods sandbox;
5. repairs generated Swift-package resource directories; and
6. resolves the committed workspace `Package.resolved` before the locked
   archive.

The iOS action delegates preparation to `ios/ci_scripts/ci_post_clone.sh`. It
recreates the ignored Firebase configuration, TDLib and TgVoip frameworks,
Flutter generated inputs, Swift packages, and CocoaPods sandbox before the
archive. GitHub's commit-height build number overrides the source build number
while the marketing version continues to use the major and minor components
from `pubspec.yaml` with a zero patch component.

The published TDLib input remains:

- Release: `tdlib-1.8.66-1b08c83bc078-rebuild-29623073124-1`
- Asset: `tdjson-macos-universal.zip`
- Archive SHA-256: `9520190747fe1f855d8445996cf92f1a57fca303a15cd3ec7c0849d9a49aaabc`
- Dylib SHA-256: `d543b42be66306dded64b55b980ec8cf88ae1d43bebf019cc3fa0ca4bb7e5482`

## Repository configuration

The workflow reads these encrypted GitHub Actions repository secrets:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`
- `FIREBASE_IOS_GOOGLESERVICE_INFO_PLIST_B64` (iOS only)
- `SENTRY_DSN` (optional)
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `IOS_SIGNING_CERTIFICATE_P12`
- `IOS_SIGNING_CERTIFICATE_PASSWORD`

The App Store Connect private key is written only to the runner's temporary
directory and removed in the final cleanup step. The Apple signing identity is
imported into a temporary keychain so ephemeral runners reuse one managed
certificate instead of consuming the Apple Development certificate quota; the
keychain and PKCS#12 are removed in the same cleanup step. `TESTFLIGHT_INTERNAL_GROUP`
and `TESTFLIGHT_EXTERNAL_GROUP` may be set as repository variables; they
default to `Internal` and `External`.

The GitHub workflows use the full Git commit height as the build number with an
offset of zero. This starts with the `1.0.0` train, after the temporary
epoch-numbered migration builds on `0.10.0`. Xcode Cloud continues to supply
its native `CI_BUILD_NUMBER` if either retained workflow is reactivated. The
marketing version keeps the major and minor components from `pubspec.yaml` and
forces the patch component to zero on both Apple platforms.

## App Store metadata prerequisite

The macOS target currently uses a temporary App Sandbox exception for
interactive screen capture. Before App Review, App Store Connect must include
App Sandbox Entitlement Usage Information that identifies the entitlement,
explains how reviewers can exercise it, why it is required, and the related
Feedback Assistant issue ID. TestFlight upload alone does not complete this
review metadata.
