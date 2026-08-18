# Mithka

English | [简体中文](README.zh-CN.md)

Mithka is an independent, cross-platform Telegram client for Android, iOS,
Windows, macOS, and Linux. It combines a Flutter interface with
[TDLib](https://core.telegram.org/tdlib) over Dart FFI to provide a compact,
native-feeling messaging experience across phones and desktops.

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
> Mithka connects to Telegram through TDLib using Telegram API credentials that
> you provide. Use it at your own risk and in accordance with Telegram’s
> [Terms of Service](https://telegram.org/tos) and
> [API Terms](https://core.telegram.org/api/terms).

## Availability

| Platform | Beta | Stable release |
| --- | --- | --- |
| Android | [Google Play Open testing](https://play.google.com/apps/testing/ad.neko.mithka) | [Google Play](https://play.google.com/store/apps/details?id=ad.neko.mithka) |
| iOS | [TestFlight](https://testflight.apple.com/join/tVC8WkbW) | [App Store](https://apps.apple.com/us/app/mithka/id6783830742) |
| Windows | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |
| macOS | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |
| Linux | [GitHub prereleases](https://github.com/iebb/mithka/releases?q=prerelease%3Atrue) | [Latest GitHub release](https://github.com/iebb/mithka/releases/latest) |

## Why “Mithka”?

The name is a small piece of wordplay inspired by the penguin mascot and two
tiny units of mass:

- The mascot suggests a **pengram**: 🐧 + *gram*. Read as *penta-gram*, it is
  approximately **5 g**.
- One **mithqāl** (مثقال), a traditional Islamic unit of mass, is approximately
  **4.6875 g**.

Derived from *mithqāl*, **Mithka** is the featherweight sitting just below the
(Tele)gram penguin on an imaginary scale.

## What Mithka offers

Mithka connects to your real Telegram account and chats through TDLib. Its
custom interface includes live chat lists and conversations, reactions,
stickers (including animated `.tgs` and `.webm` formats), voice messages, polls,
checklists, Telegram Communities, location sharing, contacts, profiles,
moments-style stories, settings, and a one-to-one calling interface.

## Architecture

- The Flutter interface lives in `lib/` and uses `provider` with
  `ChangeNotifier` for state management.
- TDLib is connected through Dart FFI in `lib/tdlib/`. A pinned native
  `libtdjson` binary is installed for each platform and is not committed to this
  repository.
- The interface adapts to light and dark themes. It uses Cupertino and custom
  components rather than Material dialogs, snackbars, or switches.

## Build from source

### 1. Add Telegram API credentials

Create your own `api_id` and `api_hash` at <https://my.telegram.org>, then place
them in the git-ignored `lib/config/secrets.dart` file:

```dart
class Secrets {
  static const int apiId = 123456;
  static const String apiHash = 'your_api_hash';
  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;
}
```

### 2. Install the native TDLib library

[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json) pins the matching
prebuilt Android, iOS, macOS, Linux, and Windows artifacts published by
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson). The helper scripts
download and verify these artifacts; this repository does not build TDLib from
source.

```bash
# Android: install one or more ABIs under android/app/src/main/jniLibs/<abi>/
scripts/build-tdjson-android.sh arm64-v8a

# iOS: install ios/tdjson/tdjson.xcframework for the Runner target
scripts/build-tdjson-ios.sh

# Desktop: write the library to the requested path (linux, macos, or windows)
scripts/build-tdjson-desktop.sh macos /tmp/libtdjson.dylib
```

These downloaded libraries are reproducible local build inputs. Keep the
library for the platform you are building, or delete it and rerun the matching
helper when you need to reclaim disk space. Legacy `.tdlib-build/` source trees,
including large `libtdcore.a` archives, are not runtime dependencies and can be
removed. See [NATIVE.md](NATIVE.md) for exact paths and cleanup guidance.

### 3. Fetch dependencies and run

```bash
flutter pub get
flutter run # Run on a connected device or simulator
```

Firebase Analytics is optional for local development. If
`android/app/google-services.json` or `ios/Runner/GoogleService-Info.plist` is
missing—or contains only an empty placeholder—the app builds and runs with
analytics disabled. Maintainers and release CI provide the real, git-ignored
configuration files automatically.

### Android release signing

Android release builds use the project’s upload key when
`android/key.properties` and its referenced keystore are available. Otherwise,
the build uses a debug signature. Neither file is committed to the repository.

## CI and releases

- `master` is the validated development branch and does not publish packages to
  GitHub, Google Play, or TestFlight.
- Pushing a validated `master` commit to `release-ios` starts Xcode Cloud
  archives for iOS and macOS and delivers them to external TestFlight testers.
  Xcode Cloud keeps the same major and minor version while setting the patch
  version to `0`.
- At 00:00 UTC each day, GitHub Actions merges new `master` commits into
  `nightly` and increments the patch version once. The workflow publishes dated
  Android, Windows, macOS, and Linux GitHub prereleases and submits the signed
  Android App Bundle to Google Play Open testing.
- Pushing to `release` publishes a dated stable, multi-platform GitHub release
  and submits the production Android App Bundle to Google Play through the same
  channel-aware workflow.

On CI runners, `secrets.dart` is generated from the `TELEGRAM_API_ID` and
`TELEGRAM_API_HASH` repository secrets.

## License and credits

Mithka is available under the [BSD 3-Clause License](LICENSE).

TDLib and the components in `third_party/` remain subject to their own licenses.
Mithka does not ship proprietary assets or trademarks from third-party apps.

## Star history

<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
