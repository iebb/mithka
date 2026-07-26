# Mithka video player example

This is a buildable Android, iOS, Linux, macOS, Windows, and web catalog for
`mithka_video_player`. It intentionally uses only Flutter's foundational
widgets and the player's custom-painted controls—there is no Material,
Cupertino, or built-in icon dependency.

The catalog demonstrates:

- a network source whose controller is owned by the player;
- a caller-created controller that is disposed by the caller;
- a custom controller builder whose result is owned by the player;
- opt-in asset and native-file sources;
- embedded and host-managed fullscreen layouts;
- lifecycle/status callbacks;
- keyboard and pointer controls; and
- multiple simultaneous, independent desktop video windows.

## Run the default network example

From this directory:

```sh
flutter pub get
flutter run -d chrome
flutter run -d macos
flutter run -d windows
flutter run -d linux
flutter run -d android
flutter run -d ios
```

The example adds the optional `mithka_video_player_fvp` adapter and calls
`MithkaFvpBackend.ensureInitialized()` before any video controller is created.
That selects FVP on Windows and Linux and keeps the official `video_player`
backend on Android, iOS, macOS, and web.
The generated Apple hosts target iOS 14.0 and macOS 11.0 because the native
thumbnail provider requires those minimums.

The iOS and macOS hosts are intentionally Swift Package Manager-only. They do
not contain Podfiles; adding one makes Flutter invoke CocoaPods and stops this
example from validating the SPM-only integration path.

Enable SPM before resolving/building either Apple host:

```sh
flutter config --enable-swift-package-manager
flutter pub get
flutter build ios --simulator --debug
flutter build macos --debug
```

The example's `dependency_overrides` pins FVP to
`../../../third_party/fvp` (`0.37.3+mithka.1`). Overrides from a dependency are
not inherited, so an application copying the optional adapter must declare its
own tested FVP source. Do not replace this with an unverified constraint and
still treat the SPM smoke build as equivalent.

The macOS Runner also invokes
`packages/mithka_video_player_fvp/tool/sanitize_mdk_macos.sh` after Flutter
embeds native frameworks. That phase removes only `/opt/homebrew/lib` and
`/usr/local/lib` from the embedded MDK binary, verifies their absence, and
re-signs the framework with the active Xcode identity before final app signing.
Keep the phase when copying this example's FVP macOS integration; otherwise a
user-installed FFmpeg can load alongside MDK's bundled FFmpeg.

## Try a local file

Pass an absolute path at compile time, then select **Local file**:

```sh
flutter run -d linux \
  --dart-define=MITHKA_VIDEO_FILE=/absolute/path/to/video.mp4
```

Use the platform-appropriate absolute path on Windows or macOS. File sources
are deliberately disabled on web because the official web backend does not
implement `VideoPlayerController.file`.

## Try an asset

Copy a test video into `assets/sample.mp4`, then add it to this example's
`pubspec.yaml`:

```yaml
flutter:
  uses-material-design: false
  assets:
    - assets/sample.mp4
```

Run the app with the matching asset key and select **Asset**:

```sh
flutter run -d macos \
  --dart-define=MITHKA_VIDEO_ASSET=assets/sample.mp4
```

The asset is not committed so downstream projects can validate their own
codec, resolution, caption, and packaging combinations without inheriting a
large binary fixture.

## Controller ownership example

Select **Owned controller**. The example creates the controller once, passes it
through `MithkaVideoPlayer.controller`, and disposes it from the host widget's
`dispose` method. The player initializes an uninitialized supplied controller,
but it never disposes a supplied controller.

Select **Controller builder** to exercise the asynchronous/custom backend
factory contract. The example keeps the builder identity stable across widget
rebuilds, while the player initializes and disposes each controller it creates.

When the player owns lifecycle behavior, custom/caller-owned controllers should
be constructed with `VideoPlayerOptions(allowBackgroundPlayback: true)` so the
player, rather than a second backend observer, owns pause/resume transitions.
Keep `lifecycleBehavior` stable during playback; changing it recreates a
source- or builder-owned controller and reapplies initial playback settings.

## Independent desktop windows

Run on Linux, macOS, or Windows and press **Open independent window** more than
once. Each press starts an independently controlled video window. The example
passes every process entry through `MithkaDesktopVideoWindows.initialize`, and
the child entry point renders inside `MithkaDesktopVideoWindowHost`. On Linux,
hidden child engines are safely reused; each new argument payload gets a fresh
keyed player subtree so the previous controller is disposed before the URI is
replaced.

The desktop runner directories in this example include the native
`multi_window_manager` hooks. Copy the relevant runner changes—not the entire
runner—when integrating the package into an existing application.

The child player listens to `currentWindowFullscreen` and sends desired state
through `setCurrentWindowFullscreen`. This keeps the fullscreen icon and
keyboard behavior aligned with native title-bar actions: `F` enters/exits,
Escape leaves fullscreen first, and another Escape closes the child window.

## Deterministic checks

The automated example tests never fetch or decode network media:

```sh
flutter analyze --fatal-infos
flutter test
flutter build web --release
```

Package CI also compiles the example for Android, iOS simulator, Linux, macOS,
and Windows so platform-runner regressions are caught early.
