# Native TDLib (tdjson) integration

Mithka talks **only** to real TDLib via Dart FFI (`lib/tdlib/td_bindings.dart`),
so each platform must ship the `tdjson` native library. There is no mock backend.

The native TDLib artifacts and source patches are kept outside this app
repository. Release assets for every supported platform live in
[`iebb/mithka-tdjson`](https://github.com/iebb/mithka-tdjson), so normal users do
not see a large vendored TDLib build tree in the app source. The checked-in
[`scripts/tdjson-manifest.json`](scripts/tdjson-manifest.json) pins one release
and its archive and payload checksums. All local and CI entry points delegate to
the same manifest-aware installer.

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
./scripts/build-tdjson-android.sh arm64-v8a
./scripts/build-tdjson-android.sh arm64-v8a armeabi-v7a x86_64
```

The helper downloads the requested manifest-pinned `tdjson-android-<abi>.zip`
assets and verifies them before installation. No Android NDK, OpenSSL source
tree, or local TDLib compilation is required. The packaged libraries target API
23; the app's minimum is API 24 because of other platform features.

## 3. iOS

On iOS the symbols are resolved from the app binary
(`DynamicLibrary.process()`), so `tdjson` must be linked into the Runner target.

1. Run `./scripts/build-tdjson-ios.sh`. It installs the manifest-pinned
   `tdjson.xcframework` from `iebb/mithka-tdjson` and verifies its contents.
2. `cd ios && pod install` (needs CocoaPods: `brew install cocoapods`).

Xcode Cloud and GitHub Actions call this same helper, so the release identity and
checksums are not duplicated in their setup scripts.

## 4. Desktop

Windows, macOS, and Linux load `tdjson` from their application bundle. Install
the matching prebuilt library into the ignored `native-libs` directory:

```sh
./scripts/build-tdjson-desktop.sh linux native-libs/libtdjson.so
./scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
./scripts/build-tdjson-desktop.sh windows native-libs/tdjson.dll
```

The release workflow packages the verified library beside the Flutter
executable (or under `Mithka.app/Contents/Frameworks` on macOS). Local builds
need the same final copy in the built bundle before the app starts. The macOS
app archive is ad-hoc signed and is not notarized.

## 5. Disk cleanup

Only the installed runtime library for the platform being built is an active
TDJSON input:

- Android: `android/app/src/main/jniLibs/<abi>/libtdjson.so`
- iOS: `ios/tdjson/tdjson.xcframework/`
- desktop: the selected library under `native-libs/`

Those paths are ignored because they are large and reproducible. Deleting one
is safe when that platform is not being built; its helper restores it from the
pinned release, at the cost of another download. Copies below Flutter's
top-level `build/` directory are derived packaging output and are also safe to
remove; Flutter or Gradle recreates them.

The legacy `.tdlib-build/` directory is no longer used by these helpers. It was
a TDLib source/build cache, and large files such as `libtdcore.a` inside it are
intermediate static archives rather than app runtime dependencies. The entire
directory can be removed without breaking the manifest-based build; it will not
be downloaded or rebuilt by the current helpers.

## 6. Run

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
