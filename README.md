# Mithka

A cross-platform (iOS + Android) Telegram client built with **Flutter** on top of
**[TDLib](https://core.telegram.org/tdlib)** via FFI, with a dense,
mobile-native messaging interface.

> **Disclaimer**
>
> Mithka is an **independent, unofficial** project. It is **not affiliated with,
> endorsed by, or connected to Telegram** in any way. "Telegram" is a trademark
> of its respective owner.
>
> Mithka is also **not affiliated with, endorsed by, sponsored by, or otherwise
> connected to Tencent or QQ**. It does not use, include, copy, or redistribute
> any proprietary QQ assets. "Tencent" and "QQ" and their associated trademarks
> and assets belong to their respective owners.
>
> The app talks to Telegram's network through TDLib using your own Telegram API
> credentials. Use it at your own risk and in accordance with Telegram's
> [Terms of Service](https://telegram.org/tos) and API
> [Terms](https://core.telegram.org/api/terms).

## Availability

Mithka is available on the App Store:
<https://apps.apple.com/us/app/mithka/id6783830742>

iOS beta builds are also available on TestFlight:
<https://testflight.apple.com/join/tVC8WkbW>

## The name

A play on small units of mass, by way of the penguin:

- The penguin mascot is a **pengram** — 🐧 + *gram*, read as **penta-gram** ≈ **5 g**.
- One **mithqāl** (مثقال), a traditional Islamic unit of mass, is **≈ 4.6875 g**.

So **Mithka** (from *mithqāl*) is the featherweight just under the (Tele)gram
penguin on the scale.

## What it is

Mithka connects to **real Telegram** (your account, your chats) through TDLib and
presents it with a custom interface: chat list, conversations with live state,
reactions and stickers (including animated `.tgs`/`.webm`), voice notes, polls
and checklists, Telegram Communities, location sharing, contacts, profiles,
moments-style stories, settings, and a 1:1 call UI.

## Architecture

- **Flutter** UI (`lib/`), state via `provider` + `ChangeNotifier`.
- **TDLib** linked through Dart FFI (`lib/tdlib/`); the native `libtdjson`
  binary is downloaded/built per platform (see below) and is **not** committed.
- All theming is adaptive (light / dark); UI components are Cupertino/custom —
  no Material dialogs, snackbars, or switches.

## Building

You need your own **Telegram API credentials** (`api_id` / `api_hash`) from
<https://my.telegram.org>. They are read from a git-ignored
`lib/config/secrets.dart`:

```dart
class Secrets {
  static const int apiId = 123456;
  static const String apiHash = 'your_api_hash';
  static bool get isConfigured => apiId != 0 && apiHash.isNotEmpty;
}
```

The TDLib native library is prepared with helper scripts (output is git-ignored).
CI downloads the latest prebuilt Android and iOS artifacts from
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson). The Android
source-build script is kept for local fallback/debug builds.

```bash
# Android local fallback (per ABI) — produces android/app/src/main/jniLibs/<abi>/libtdjson.so
scripts/build-tdjson-android.sh arm64-v8a

# iOS — downloads ios/tdjson/tdjson.xcframework consumed by the Runner
scripts/build-tdjson-ios.sh
```

Then run:

```bash
flutter pub get
flutter run            # on a connected device / simulator
```

Firebase Analytics is optional for local builds. If
`android/app/google-services.json` or `ios/Runner/GoogleService-Info.plist` is
missing (or is only an empty placeholder), the app builds and runs with
analytics disabled. Maintainers and release CI provide the real, git-ignored
configuration files automatically.

### Release signing (Android)

Release builds are signed with the project's upload key when
`android/key.properties` (and the referenced keystore) are present; otherwise a
debug signature is used. Neither the keystore nor `key.properties` is committed.

## CI

`master` does not build Android packages. At 00:00 and 12:00 UTC each day,
GitHub Actions merges new `master` commits into `nightly` and increments the
app's patch version once; `nightly` publishes dated GitHub prereleases. Xcode
Cloud keeps the same major/minor version but forces the iOS patch to `0`. Pushes
to `release` publish dated stable GitHub releases. Google Play publishing is
split into a separate guarded, manual-only workflow and is not triggered by
release pushes.
`secrets.dart` is generated on the runner from the `TELEGRAM_API_ID` /
`TELEGRAM_API_HASH` repository secrets.

## License & credits

TDLib is © Telegram, used under its own license. This repository contains only
original, independently-written code; it ships no third-party app's proprietary
assets or trademarks.

## Star History
<a href="https://www.star-history.com/?repos=iebb%2Fmithka&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&theme=dark&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=iebb/mithka&type=date&legend=top-left&sealed_token=1PtDobhZ9XXhT7wgN5YMBVDBa9coSe7MIPcmYtH78U0zAurRU1n2ZU9n_8HKCB7KYraJOet0tyGPTh3jXh_oq-RkR9els5W0T0EDz-_nvt0ce-n1AvOOKgljMdSc-FOc5j0X3RVcRmyyq0qoVZBdWqIPFKMpBvKO8yoRgRc9i9ck-r4-RmWM0FqWLjXG" />
 </picture>
</a>
