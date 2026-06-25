# Native TDLib (tdjson) integration

Mithka talks **only** to real TDLib via Dart FFI (`lib/tdlib/td_bindings.dart`),
so each platform must ship the `tdjson` native library. There is no mock backend.

The native TDLib artifacts are kept outside this app repository. iOS release
assets live in [`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson), so
normal users do not see a large vendored TDLib binary in the app source tree.

## 1. Credentials

```sh
cp lib/config/secrets_example.dart lib/config/secrets.dart
```

Fill in your `apiId` / `apiHash` from <https://my.telegram.org> → API tools.
`secrets.dart` is git-ignored. Until it's configured, the app launches straight
to a "尚未配置" notice (TDLib is never touched), which is handy for UI work.

## 2. Android

The FFI layer loads `libtdjson.so` by name, so the per-ABI libraries just need to
live under `android/app/src/main/jniLibs/<abi>/libtdjson.so` — the Gradle plugin
bundles them automatically.

```sh
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<version>
./scripts/build-tdjson-android.sh           # arm64-v8a armeabi-v7a x86_64
```

(Building tdjson needs a cross-compiled OpenSSL + zlib per ABI — see the official
guide: <https://tdlib.github.io/td/build.html>. `minSdk` is pinned to 21.)

## 3. iOS

On Apple platforms the symbols are resolved from the app binary
(`DynamicLibrary.process()`), so `tdjson` must be linked into the Runner target.

1. Run `./scripts/build-tdjson-ios.sh`. It downloads the prebuilt
   `tdjson.xcframework` from `iebb/mithka-tdjson` unless
   `TDJSON_XCFRAMEWORK_URL` overrides the source.
2. `cd ios && pod install` (needs CocoaPods: `brew install cocoapods`).

To refresh the prebuilt artifact, rebuild TDLib separately, package
`tdjson.xcframework` in the `mithka-tdjson` repo, upload a new release asset, and
bump the default URL in `scripts/build-tdjson-ios.sh` and
`ios/ci_scripts/ci_post_clone.sh`.

## 4. Run

```sh
flutter run            # pick an Android emulator or iOS simulator/device
```

The auth flow (phone → code → password) drives TDLib's `authorizationState`, and
the session persists in the per-account TDLib database under the app's support dir.

## Architecture notes

- `td_bindings.dart` binds the four stable `tdjson` C entry points.
- `td_client.dart` runs the blocking `td_receive` loop on a **dedicated isolate**
  (it re-opens the process-global library there) and posts events back to the main
  isolate, which correlates `@extra` responses, bootstraps `setTdlibParameters`
  per account, and broadcasts updates to a `Stream`. Multi-account "slots" persist
  in SharedPreferences, mirroring the Swift `TDLibClient`.
