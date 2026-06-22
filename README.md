# Mithkal

A cross-platform (iOS + Android) Telegram client built with **Flutter** on top of
**[TDLib](https://core.telegram.org/tdlib)** via FFI, with a UI **inspired by the
look and feel of QQ / WeChat-style messengers**.

> **Disclaimer**
>
> Mithkal is an **independent, unofficial** project. It is **not affiliated with,
> endorsed by, or connected to Tencent, QQ, WeChat, or Telegram** in any way. The
> interface is merely *inspired by* the visual style of QQ-style messengers — no
> QQ/WeChat/Tencent code, assets, trademarks, or branding are used. "QQ",
> "WeChat", "Tencent" and "Telegram" are trademarks of their respective owners.
>
> The app talks to Telegram's network through TDLib using your own Telegram API
> credentials. Use it at your own risk and in accordance with Telegram's
> [Terms of Service](https://telegram.org/tos) and API
> [Terms](https://core.telegram.org/api/terms).

## What it is

Mithkal connects to **real Telegram** (your account, your chats) through TDLib and
presents it with a QQ-inspired interface: chat list, conversations with live
state, reactions and stickers (including animated `.tgs`/`.webm`), voice notes,
polls and checklists, location sharing, contacts, profiles, moments-style
stories, settings, and a 1:1 call UI.

## Architecture

- **Flutter** UI (`lib/`), state via `provider` + `ChangeNotifier`.
- **TDLib** linked through Dart FFI (`lib/tdlib/`); the native `libtdjson`
  binary is built per platform (see below) and is **not** committed.
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

The TDLib native library is built with the helper scripts (output is git-ignored):

```bash
# Android (per ABI) — produces android/app/src/main/jniLibs/<abi>/libtdjson.so
scripts/build-tdjson-android.sh arm64-v8a

# iOS — produces the libtdjson framework consumed by the Runner
scripts/build-tdjson-ios.sh
```

Then run:

```bash
flutter pub get
flutter run            # on a connected device / simulator
```

### Release signing (Android)

Release builds are signed with the project's upload key when
`android/key.properties` (and the referenced keystore) are present; otherwise a
debug signature is used. Neither the keystore nor `key.properties` is committed.

## CI

GitHub Actions runs format + analyze + tests on the `release` branch (see
`.github/workflows/`). `secrets.dart` is generated on the runner from the
`TELEGRAM_API_ID` / `TELEGRAM_API_HASH` repository secrets.

## License & credits

TDLib is © Telegram, used under its own license. This repository contains only
original, independently-written code; it ships no third-party app's proprietary
assets or trademarks.
