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
assigns the processed build to both `Internal` and `External` TestFlight groups,
creates the Beta App Review submission for external testing, and verifies that
App Store Connect reports internal testing. Beta App Review is Apple's call, so
its outcome only gates external testing: a rejection, a submission limit, or a
sibling build already in review is logged and the run still passes. The former
macOS Xcode Cloud workflow is retained in App Store Connect in a deactivated
state for rollback and configuration history.

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
build to the same Internal and External TestFlight groups. It also creates the
external Beta App Review submission on the same best-effort terms.

## Deterministic build preparation

The action uses Flutter 3.44.2 and delegates source preparation to
`ci_scripts/macos_post_clone.sh`. The helper:

1. writes `lib/config/secrets.dart` without logging its values;
2. runs the shared manifest-aware installer for the universal TDLib artifact;
3. generates the release Flutter/Xcode configuration;
4. restores the committed CocoaPods sandbox;
5. repairs generated Swift-package resource directories; and
6. resolves the committed workspace `Package.resolved` before the locked
   archive.

The iOS action delegates preparation to `ios/ci_scripts/ci_post_clone.sh`. It
recreates the ignored Firebase configuration, TDLib and TgVoip frameworks,
Flutter generated inputs, Swift packages, and CocoaPods sandbox before the
archive. GitHub's commit-height build number overrides the source build number,
while the marketing version keeps the complete `X.Y.Z` from the checked-out
branch's `pubspec.yaml`, including the patch.

The published TDLib release identity, source provenance, asset names, and
checksums live only in `scripts/tdjson-manifest.json`. Both Apple post-clone
hooks call the normal platform wrappers, which delegate download, extraction,
and verification to `scripts/install-tdjson-artifact.py`. Updating the pin is
therefore one manifest change rather than a set of workflow-specific edits.

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
Apple marketing version is identical on iOS and macOS: preserve the exact
`X.Y.Z` from the checked-out branch's `pubspec.yaml`, removing only its optional
`+build` suffix. This applies to nightly, master, release (including platform
release branches), manual dispatches, and missing branch names alike; no branch
forces a zero patch. Nightly sync (`.github/workflows/sync-nightly.yml`) computes
and stamps the nightly branch's patch before the GitHub release and Apple jobs
read it. The helper does not look up the latest GitHub release or infer a patch
from a build number: building an older source checkout still uses that older
source version. For example, a computed nightly version of `1.8.4` remains
`1.8.4`, not `1.8.0`.

App Store Connect distinguishes marketing versions from build numbers. Keeping
each nightly patch can open a separate marketing/review train for each patch;
external testing remains subject to Apple's Beta App Review requirements.
`scripts/apple_marketing_version.sh` is the single rule, applied by both
post-clone hooks in GitHub Actions and the retained Xcode Cloud workflow. Both
GitHub workflows verify the archived app's `CFBundleShortVersionString` before
uploading it to App Store Connect and use the same exact version when selecting
the processed build for TestFlight groups.

## App Store metadata prerequisite

The macOS target currently uses a temporary App Sandbox exception for
interactive screen capture. Before App Review, App Store Connect must include
App Sandbox Entitlement Usage Information that identifies the entitlement,
explains how reviewers can exercise it, why it is required, and the related
Feedback Assistant issue ID. TestFlight upload alone does not complete this
review metadata.

The guarded App Store review helper accepts `--platform IOS` or
`--platform MAC_OS`. It verifies the selected platform on the uploaded build, scopes store
version metadata and review submissions to that platform, and uses the matching
GitHub archive job. Both platforms preserve the complete source marketing
version described above, so `--binary-version` carries what the binary actually
holds (source `1.2.1` uploads as `1.2.1` on every branch), while `--version`
names the App Store listing.
