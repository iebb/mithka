# Mithka

![Mithka — an independent Telegram client](docs/images/mithka-github-banner.png)

English | [简体中文](README.zh-CN.md)

**Mithka** is a fast, compact, cross-platform Telegram client built with Flutter
and [TDLib](https://core.telegram.org/tdlib) over Dart FFI. It runs natively on
Android, iOS, macOS, Windows, Linux, and HarmonyOS Next—adapting from single-hand
phone navigation to multi-pane tablet and desktop workspaces.

![Mithka desktop, iPad, and iPhone Duo layout mockups](docs/images/mithka-github-devices.png)

*Illustrative layout previews using fictional conversations. Device frames are
mockups rather than live screenshots.*

> [!IMPORTANT]
> Mithka is an independent, unofficial project. It is not affiliated with,
> endorsed by, or connected to Telegram. “Telegram” is a trademark of its
> respective owner.
>
> Mithka is also not affiliated with, endorsed by, sponsored by, or otherwise
> connected to Tencent or QQ. It does not use, include, copy, or redistribute
> proprietary QQ assets. “Tencent,” “QQ,” and their related trademarks and
> assets belong to their respective owners.
>
> When building from source, Mithka connects to Telegram through TDLib using API
> credentials that you provide. Use it in accordance with Telegram’s
> [Terms of Service](https://telegram.org/tos) and
> [API Terms](https://core.telegram.org/api/terms).

---

## Downloads

| Platform | Beta / Nightly | Stable |
| --- | --- | --- |
| **Android** | [Google Play Open testing](https://play.google.com/apps/testing/ad.neko.mithka) · [GitHub APKs](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Google Play](https://play.google.com/store/apps/details?id=ad.neko.mithka) · [GitHub release](https://github.com/iebb/mithka/releases/latest) |
| **iOS & iPadOS** | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) | [App Store](https://apps.apple.com/us/app/mithka/id6783830742) |
| **macOS 12+** (`arm64`, `x64`) | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) · [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Mac App Store](https://apps.apple.com/us/app/mithka/id6783830742?platform=mac) · [GitHub release](https://github.com/iebb/mithka/releases/latest) |
| **Windows** (`x64`, `arm64`) | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |
| **Linux** (`x64`, `arm64`) | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |
| **HarmonyOS Next** (`.hap`) | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |

iPhone, iPad, and Mac share one App Store listing, and the TestFlight link
covers all three.

### Desktop packaging notes

- **macOS**: The Mac App Store build is the recommended install; it updates
  through the App Store. The GitHub release also ships per-architecture `.zip`
  archives. They are ad-hoc signed and not notarized, so macOS asks you to
  approve the first launch in **System Settings → Privacy & Security**.
- **Windows** ships both per-user `setup.exe` installers (no administrator
  rights required; registers Start Menu shortcuts and Installed Apps) and
  portable ZIP archives for `x64` and `arm64`.
- **Linux** ships `x64` and `arm64` AppImages alongside portable tarballs,
  validated in CI against Ubuntu 24.04 (`chmod +x Mithka.AppImage` and run from
  a writable directory).
- **Self-updates on Windows & Linux**: **Settings → About → Check for Updates**
  fetches the latest stable GitHub release for your CPU architecture, verifies
  its published SHA-256 digest, swaps the installation atomically, and
  relaunches. Package-manager, Flatpak, or Snap installs open the release page
  instead of overwriting files managed externally.

---

## Highlights

- **Real TDLib core, multi-account ready**: Dedicated background receive isolate
  over `libtdjson`, instant account switching, passkey and QR sign-in, SOCKS5 /
  HTTP / MTProto / Web proxies, and encrypted session backup/import.
- **Rich messaging & composer**: Replies, quotes, reactions, custom emoji,
  animated `.tgs` and `.webm` stickers, sticker studio, GIFs, polls, checklists,
  scheduled sends, rich-text formatting, LaTeX math, and inline/reply bots.
- **Media, voice & calls**: Streaming fullscreen video player with Picture-in-Picture
  and desktop pop-out windows, voice and circular video notes, built-in music
  player with system Now Playing controls, and 1-to-1 / group voice calls.
- **Communities, topics & feeds**: Chat folders, forum topic strips, Telegram
  Communities, story and channel photo/video feeds, Telegram Mini Apps, and
  optional on-device or user-configured AI translation and unread summaries.
- **Intentional design system**: Explicit typography, spacing, corner-radius,
  and light/dark palette tokens (`lib/theme/app_theme.dart`), custom modal
  dialogs and controls, and project-owned vector icons (`AppIcon` /
  `HeroAppIcons`) rather than stock Material or Cupertino icon sets.
- **Localized in 8 languages**: English, Simplified Chinese, Traditional
  Chinese, Japanese, Korean, German, French, and Spanish.

---

## Why “Mithka”?

The name is a small piece of wordplay inspired by the penguin mascot and two
tiny units of mass:

- The mascot suggests a **pengram**: 🐧 + *gram*. Read as *penta-gram*, that is
  roughly **5 g**.
- One **mithqāl** (مثقال), a traditional unit of mass, is **4.6875 g**.

Derived from *mithqāl*, **Mithka** is the featherweight sitting just lighter
than the 5-gram penguin on an imaginary balance scale.

---

## Architecture & Project Layout

```text
mithka/
├── lib/
│   ├── app/              # App shell, split-pane layout, deep links, desktop windows
│   ├── auth/             # Login flow, multi-account store, QR & passkey sign-in
│   ├── bot_api/          # Bot API account mode & local TD-compatible adapter
│   ├── call/             # 1-to-1 and group call UI & native VoIP bridges
│   ├── channels/         # Forum/topic navigation and channel topic views
│   ├── chat/             # Conversation core (ChatView, ChatViewModel, session cache)
│   │   ├── admin/        # Chat info, members, permissions, and moderation logs
│   │   ├── ai_translation/ # Optional message translation & unread chat summaries
│   │   ├── appearance/   # Chat themes, wallpapers, and bubble previews
│   │   ├── composer/     # Input bar, voice/video capture, polls, rich composer
│   │   ├── links_search/ # t.me/tg:// router, link previews, internal browser, search
│   │   ├── media/        # Video player, stream server, music player, image editor
│   │   ├── messages/     # Message bubbles, albums, reactions, replies, action menus
│   │   ├── mini_apps/    # Telegram Mini Apps, bot platform, and invoice checkout
│   │   └── stickers/     # Stickers, custom emoji, GIFs, and sticker set studio
│   ├── chats/            # Chat list, folders, archive, and global search
│   ├── communities/      # Telegram Communities hierarchy and management
│   ├── components/       # Project-owned UI primitives, dialogs, and AppIcon set
│   ├── config/           # Build flags and git-ignored API credentials
│   ├── contacts/         # Contacts, groups/channels/bots directory, and add-people
│   ├── l10n/             # Generated localization keys and runtime loader
│   ├── media/            # Asset picker, camera capture, and media metadata probes
│   ├── moments/          # Stories viewer, story authoring, and channel Moments feed
│   ├── notifications/    # Local/push notifications and per-scope mute settings
│   ├── platform/         # Native method-channel bridges across mobile & desktop
│   ├── profile/          # User/chat profiles, QR cards, and collectible gifts
│   ├── security/         # Biometric/passcode lock and auto-clearing clipboard
│   ├── settings/         # Appearance, privacy, storage, proxy, AI, and blocking
│   ├── tdlib/            # Dart FFI bindings, background receive isolate, models
│   ├── theme/            # Design tokens, light/dark palettes, and cloud themes
│   └── update/           # GitHub release feed and Windows/Linux self-updater
├── apple/                # Shared Swift bridges compiled into both iOS and macOS
├── android/ ios/ macos/  # Platform runners and native plugins
├── linux/ windows/ ohos/ # Desktop and HarmonyOS Next runners
├── translations/         # Source XML string catalogues (8 locales) & check tools
├── scripts/              # Manifest-pinned tdjson installers & release automation
└── test/                 # Domain-organized unit, widget, and release-script suites
```

State is managed with `provider` and scoped `ChangeNotifier` view models. Native
TDLib calls never block the UI isolate: `lib/tdlib/td_client.dart` runs the
blocking `td_receive` loop on a dedicated background isolate, correlates
`@extra` request/response pairs, and broadcasts typed updates per account slot.

---

## Build from Source

### Prerequisites

- Flutter SDK (see `.github/workflows/quality.yml` for the pinned stable version)
- Platform toolchain for your target OS (Xcode for iOS/macOS, Android SDK,
  Visual Studio C++ workload for Windows, or GTK3 development headers for Linux)
- Python 3 (used by the manifest-pinned `tdjson` installer and verification tools)

### 1. Configure Telegram API credentials

Obtain your own `api_id` and `api_hash` from <https://my.telegram.org>, copy the
example file, and fill in your credentials (`lib/config/secrets.dart` is
git-ignored):

```bash
cp lib/config/secrets_example.dart lib/config/secrets.dart
```

```dart
class Secrets {
  static const int apiId = 123456;
  static const String apiHash = 'your_api_hash';
  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;
}
```

*(Tip: if you leave `secrets_example.dart` unchanged, the app still compiles and
launches into a credential setup screen—useful for pure UI work and running
widget tests.)*

### 2. Install the prebuilt TDLib (`tdjson`) binary

Mithka does not require compiling TDLib locally.
[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json) pins prebuilt,
SHA-256-verified binaries published in
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson):

```bash
# Android (installs under android/app/src/main/jniLibs/<abi>/)
./scripts/build-tdjson-android.sh arm64-v8a

# iOS (installs ios/tdjson/tdjson.xcframework, then install pods)
./scripts/build-tdjson-ios.sh
(cd ios && pod install)

# Desktop (macos, linux, or windows; optional arch: x64 or arm64)
./scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
./scripts/build-tdjson-desktop.sh linux native-libs/libtdjson.so x64
./scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll x64
```

See [NATIVE.md](NATIVE.md) for bundle placement details and disk cleanup tips.

### 3. Install dependencies and run

```bash
flutter pub get
flutter run
```

### Optional local configuration

- **Firebase Analytics**: Optional for local builds. When
  `android/app/google-services.json` or `ios/Runner/GoogleService-Info.plist` is
  absent, Mithka builds and runs normally with analytics disabled.
- **Android release signing**: Uses `android/key.properties` and its keystore if
  present, falling back to debug signing for local builds.
- **Compile-time Terms boundary**: Official builds, nightlies, TestFlight, and
  store releases always compile with `allowTelegramTosViolations = false`
  (`lib/config/build_flags.dart`). Any contributor code covered by Telegram API
  Terms section 1.4 is completely inert unless explicitly self-built with
  `--dart-define=I_DONT_FUCKING_CARE_ABOUT_TOS=true` (which does not make such
  behavior compliant with Telegram’s terms).

---

## Development & Verification

Before opening a pull request, run the local checks matching CI (`quality.yml`):

```bash
# Format & static analysis
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze

# Localization & asset checks
python3 translations/tools/check.py
python3 translations/tools/gen_assets.py --check
python3 tool/check_l10n_strings.py
python3 tool/optimize_app_artwork.py --check

# Unit & widget test suite
flutter test --concurrency=4
```

Design token conventions live in [DESIGN.md](DESIGN.md), localization workflows
in [docs/localization.md](docs/localization.md), test organization in
[test/README.md](test/README.md), and repository/PR rules in
[AGENTS.md](AGENTS.md).

---

## Versioning, CI & Releases

- **`master` holds the next minor (`X.Y.0`)**: Validated on every push and PR by
  `Quality` and platform build workflows without publishing store artifacts
  directly.
- **Daily nightly builds (`sync-nightly.yml`, 00:00 UTC / 09:00 Tokyo)**: When
  `master` has new commits, GitHub Actions merges `master` into `nightly`,
  increments the patch version once (`X.Y.1`, `X.Y.2`, …; or ships `X.Y.0` on
  the first sync of a new minor), and dispatches multi-platform GitHub
  prereleases, Google Play Open testing, and iOS/macOS TestFlight uploads. Patch
  numbers are never rewritten back to `.0`.
- **Twice-monthly store releases (`weekly-store-release.yml`, 1st & 15th at
  09:00 Tokyo)**: Tags an immutable `store-vX.Y.Z` release above every patch
  used on that minor, submits that exact version to the App Store (iOS and
  macOS), Google Play, and GitHub Releases, then hands the HarmonyOS hap to
  Huawei AppGallery (`appgallery-submit.yml`). It then advances `master` to
  `X.(Y+1).0` and immediately dispatches `sync-nightly.yml` so beta testers
  receive `X.(Y+1).0` the same day.

---

## License & Credits

Mithka is licensed under the [BSD 3-Clause License](LICENSE).

TDLib and components under `third_party/` remain governed by their respective
licenses. Mithka does not distribute proprietary assets or trademarks from
third-party applications.

## Star History

<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
