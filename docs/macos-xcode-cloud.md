# macOS Xcode Cloud and TestFlight

Mithka uses GitHub Actions as its active macOS TestFlight delivery path:

- Every push to `master` runs `.github/workflows/macos-testflight.yml` and uploads
  an internal-only build.
- Manual dispatches use the same workflow and can opt out of the permanent
  internal-only restriction when an external beta is intended.
- Xcode Cloud can be configured as an alternative, but must not upload macOS
  builds concurrently with the GitHub workflow.

Both paths use the version in `pubspec.yaml`, Flutter 3.44.2, and the pinned patched TDLib source identified in the CI scripts. GitHub Actions uses an epoch-seconds build number, while Xcode Cloud uses its own monotonically increasing integer build number.

## Repository-side setup

Xcode Cloud automatically runs `ci_scripts/ci_post_clone.sh`. The dispatcher preserves the existing iOS setup and selects `ci_scripts/macos_post_clone.sh` when the macOS workflow sets `MITHKA_CI_PLATFORM` to `macos`.

The macOS helper:

1. Installs the pinned Flutter SDK and native build tools when necessary.
2. Writes `lib/config/secrets.dart` without logging secret values.
3. Builds and verifies a universal `arm64` and `x86_64` patched TDLib dylib.
4. Generates the release Flutter/Xcode configuration.
5. Restores the CocoaPods sandbox used by desktop-only plugins.

## Optional Xcode Cloud alternative

Before switching to Xcode Cloud, remove or disable the GitHub workflow's
`push` trigger. Then create a separate macOS workflow in Xcode or App Store
Connect with these settings:

- Repository branch: `master` after the GitHub push trigger is disabled (or
  manual start while validating it).
- Project or workspace: `macos/Runner.xcworkspace`.
- Scheme: `Runner`.
- Platform and destination: macOS, Any Mac.
- Action: Archive using the Release configuration.
- Xcode and macOS: a stable image compatible with Flutter 3.44.2; avoid beta images.
- Post-action: Distribute to TestFlight, selecting only the intended internal group during initial validation.

Before the first distribution, open App Store Connect → Xcode Cloud → Settings
→ Build Number and set **Next Build Number** to an integer greater than every
macOS build already uploaded for Mithka. Xcode Cloud starts at `1` by default,
but macOS build numbers must increase across app versions. If the GitHub
uploader is re-enabled later, keep only one automatic uploader active and make
its next build number greater than every previous macOS upload.

Add these workflow environment variables and mark both as secret:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

Also add `MITHKA_CI_PLATFORM` with the non-secret value `macos`. `SENTRY_DSN` is optional and should be secret when configured. Xcode Cloud manages the signing certificate and provisioning profile; App Store Connect API-key secrets used by GitHub Actions are not needed in Xcode Cloud.

The first macOS build compiles TDLib and can be substantially slower than later Flutter-only build steps. Xcode Cloud does not share the GitHub Actions TDLib cache.

## App Store metadata prerequisite

The macOS target currently uses a temporary App Sandbox exception for interactive screen capture. Before App Review, App Store Connect must include App Sandbox Entitlement Usage Information that identifies the entitlement, explains how reviewers can exercise it, why it is required, and the related Feedback Assistant issue ID. TestFlight upload alone does not complete this review metadata.
