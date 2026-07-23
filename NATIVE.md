# Native TDLib (tdjson) integration

Mithka talks **only** to real TDLib via Dart FFI (`lib/tdlib/td_bindings.dart`),
so each platform must ship the `tdjson` native library. There is no mock backend.

The native TDLib artifacts and source patches are kept outside this app
repository. Android and iOS release assets live in
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson), so normal users do
not see a large vendored TDLib binary in the app source tree. Desktop builds
fetch the same pinned patch set and compile TDLib for the target operating
system.

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
guide: <https://tdlib.github.io/td/build.html>. `minSdk` is pinned to 23.)

GitHub Actions does not run this source build in the app repo. It resolves the
pinned `iebb/mithka-tdjson` release, caches by that release tag, and downloads
`tdjson-android-<abi>.zip`.

## 3. iOS

On iOS the symbols are resolved from the app binary
(`DynamicLibrary.process()`), so `tdjson` must be linked into the Runner target.

1. Run `./scripts/build-tdjson-ios.sh`. It downloads the prebuilt
   `tdjson.xcframework` from `iebb/mithka-tdjson` unless
   `TDJSON_XCFRAMEWORK_URL` overrides the source.
2. `cd ios && pod install` (needs CocoaPods: `brew install cocoapods`).

Xcode Cloud uses the same pinned release artifact by default. Set
`TDJSON_XCFRAMEWORK_URL` only when a build must pin a specific artifact.

## 4. Desktop

Windows, macOS, and Linux load `tdjson` from their application bundle. Build the
matching patched library into the ignored `native-libs` directory:

```sh
./scripts/build-tdjson-desktop.sh linux native-libs/libtdjson.so
./scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
./scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll
```

The release workflow builds one host per runner, packages the library beside
the Flutter executable (or under `Mithka.app/Contents/Frameworks` on macOS), and
publishes Windows x64, universal macOS, and Linux x64 archives with each GitHub
release. Local builds need the same final copy into the built bundle before the
app starts. The macOS archive is ad-hoc signed and is not notarized.

## 5. Run

```sh
flutter run            # pick an available mobile or desktop target
```

The auth flow (phone → code → password) drives TDLib's `authorizationState`, and
the session persists in the per-account TDLib database under the app's support dir.

## Architecture notes

- `td_bindings.dart` binds the four stable `tdjson` C entry points plus the
  optional Mithka session-backup and transfer-boost exports.
- `td_client.dart` runs the blocking `td_receive` loop on a **dedicated isolate**
  (it re-opens the process-global library there) and posts events back to the main
  isolate, which correlates `@extra` responses, bootstraps `setTdlibParameters`
  per account, and broadcasts updates to a `Stream`. Multi-account "slots" persist
  in SharedPreferences, mirroring the Swift `TDLibClient`.
