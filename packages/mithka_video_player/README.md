# mithka_video_player

`mithka_video_player` is a reusable, responsive Flutter player surface built on
the `video_player` controller contract. It provides production controls,
keyboard and pointer interaction, accessibility semantics, lifecycle handling,
and optional independent desktop windows while keeping application navigation,
stream authorization, analytics, and sharing outside the package.

The UI is made from foundational Flutter widgets and custom-painted glyphs. It
does not require Material, Cupertino, or their built-in icon fonts.

## Capabilities

- Network, asset, native-file, caller-owned controller, and controller-builder
  sources.
- Play/pause, replay, mute, volume, playback speed, seek, buffered progress,
  captions, fullscreen callbacks, and scrub previews where supported.
- Compact controls for narrow layouts and larger controls with inline volume
  on wide tablet/desktop layouts.
- Keyboard, pointer, touch, touch-region double-tap seek, desktop double-click
  fullscreen, opt-in mouse-wheel volume, RTL timeline, and adjustable
  screen-reader semantics.
- Configurable autoplay, looping, initial position, seek interval, control-hide
  delay, fit, alignment, colors, labels, focus, lifecycle policy, and builders.
- Official `video_player` backends on Android, iOS, macOS, and web, with an
  optional sibling FVP adapter for Linux, Windows, and deliberate native
  backend overrides.
- Multiple independently controlled Linux, macOS, and Windows player windows.
- No network access in unit tests; platform builds live in the example and CI.

## Platform matrix

| Platform | Playback backend | Network | Asset | File | Separate windows | Scrub images |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Android | official `video_player` / ExoPlayer | Yes | Yes | Yes | No | Yes |
| iOS | official `video_player` / AVPlayer | Yes | Yes | Yes | No | Yes |
| macOS | official `video_player` / AVPlayer | Yes | Yes | Yes | Yes | Yes |
| Web | official `video_player_web` | Yes | Yes | No | No | Time only |
| Windows | FVP through the optional adapter | Yes | Yes | Yes | Yes | Time only |
| Linux | FVP through the optional adapter | Yes | Yes | Yes | Yes | File only |

“Time only” means scrubbing and seeking still work, but the default preview
shows the target time without a decoded thumbnail. Linux's native decoder can
seek local files but does not accept network URIs. Windows can extract a local
file's first frame, but its native API cannot extract nonzero scrub positions,
so the player deliberately uses time-only previews there. Android, iOS, and
macOS support seekable native previews for ordinary network/file sources.

Assets, authenticated sources with HTTP headers, web, and other custom media
should provide an injected `thumbnailProvider`; provider failure degrades to a
time-only preview without blocking seek or playback.

The actual codecs and streaming formats are determined by the selected native
backend and, on web, by the user's browser. Do not infer support from a file
extension alone.

## Installation

This repository currently keeps the package private (`publish_to: none`). Use a
path dependency in a monorepo or a Git dependency from another project:

```yaml
dependencies:
  mithka_video_player:
    path: ../mithka/packages/mithka_video_player
```

No backend initialization is required when a host uses the official Android,
iOS, macOS, or web `video_player` implementations.

### Optional FVP backend

Windows and Linux hosts, and applications that deliberately select FVP on
another native platform, must add the sibling adapter. Keep FVP as a direct
dependency of the final application so its native assets are included
correctly on Flutter 3.27 and newer:

```yaml
dependencies:
  mithka_video_player_fvp:
    path: ../mithka/packages/mithka_video_player_fvp
  fvp: ^0.37.3

# Required when reproducing this repository's tested Apple SPM builds.
dependency_overrides:
  fvp:
    path: ../mithka/third_party/fvp
```

The final application—not a transitive package—must declare that override.
This repository validates `third_party/fvp` version `0.37.3+mithka.1`, which
contains its current Apple Swift Package Manager resource/framework fixes. If
you select a different FVP release or fork, repeat both iOS and macOS SPM
builds; a compatible Dart constraint alone does not validate native packaging.

Initialize the adapter before any controller is created. Do this for every
Flutter engine entry point, including desktop child windows:

```dart
import 'package:flutter/widgets.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:mithka_video_player_fvp/mithka_video_player_fvp.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  MithkaFvpBackend.ensureInitialized();

  final child = await MithkaDesktopVideoWindows.initialize(arguments);
  // Choose the main or child widget tree, then call runApp(...).
}
```

The default backend configuration selects FVP only on Windows and Linux. It
leaves the official backend active everywhere else. Advanced projects can pass
`MithkaFvpConfiguration` to set decoder preferences, decoded-size bounds,
low-latency mode, fast seeking, or documented libmdk options. Configure global
backend options once, before creating the first controller.

Do not add the adapter to an application that only needs official backends.
Flutter discovers transitive native plugins before Dart tree shaking; runtime
platform selection does not remove FVP's native binaries from other platform
artifacts. See the
[`mithka_video_player_fvp` README](../mithka_video_player_fvp/README.md) for the
complete integration contract, including its required macOS post-embed
packaging phase.

## Embedded player

```dart
MithkaVideoPlayer(
  source: const MithkaVideoSource.network(
    'https://media.example/video.mp4',
    httpHeaders: {'Authorization': 'Bearer short-lived-token'},
  ),
  width: 1920,
  height: 1080,
  autoplay: false,
  looping: false,
  initialMuted: false,
  accentColor: const Color(0xFF61D6C8),
  onReady: (controller) {
    // The controller is initialized and the controls are ready.
  },
  onEnded: () {
    // Advance a playlist or update application state.
  },
  onToggleFullscreen: () {
    // Fullscreen layout/navigation belongs to the host application.
  },
)
```

Pass the real encoded width and height when known. The player uses them for the
initial aspect ratio and scrub-preview geometry; otherwise it falls back to the
controller's reported ratio and then 16:9.

### Sources

```dart
const network = MithkaVideoSource.network(
  'https://media.example/video.mp4',
  httpHeaders: {'X-Playback-Token': '...'},
);

const asset = MithkaVideoSource.asset(
  'videos/intro.mp4',
  package: 'feature_assets', // Omit for an app-owned asset.
);

const file = MithkaVideoSource.file('/absolute/path/to/video.mp4');

final fromUri = MithkaVideoSource.uri(uri);
```

`MithkaVideoSource.network` also accepts the official controller options and a
`Future<ClosedCaptionFile>`. Treat HTTP header maps as immutable after creating
a source. Avoid embedding long-lived credentials in URLs, logs, desktop-window
titles, or analytics.

Asset keys must be declared by the host application's `pubspec.yaml`. File
sources require a native path and intentionally throw `UnsupportedError` on
web unless the host supplies a compatible custom controller.

### Controller ownership

The ownership contract is explicit:

| Input | Initialization | Disposal |
| --- | --- | --- |
| Only `source` | Player initializes | Player disposes |
| `controller` | Player initializes only if needed | Caller disposes |
| `controllerBuilder` | Player initializes | Player disposes |

A direct supplied controller takes precedence over the source factory. The
source still describes identity and thumbnail/caption metadata. When replacing
a direct controller, retain it until the old player has detached and dispose it
from the owning widget or service.

Use a controller builder when a project needs a custom backend, caching layer,
signed-URL refresh, or test double but wants the player to own that controller's
lifetime. Keep the builder function's identity stable across rebuilds; creating
a new closure in every `build` call replaces and disposes the controller.

Source- and builder-owned controllers are recreated when their source, builder,
or `lifecycleBehavior` changes, and initial volume, speed, position, looping,
and autoplay configuration is applied again. Treat those inputs as stable
during ordinary playback if preserving the current position matters. Changing
the source while a direct caller-owned controller is attached does not replace
that controller.

For `pauseAndResume` or `pause`, the built-in source factory creates a
controller with `allowBackgroundPlayback: true` so the player is the sole
lifecycle owner. A custom builder or caller-owned controller must be created
with the same option for those policies. For `delegateToController`, configure
the controller/backend's own lifecycle behavior instead. The player cannot
reconstruct a caller-owned controller when `lifecycleBehavior` changes, so the
caller must replace it if its construction options need to change.

Player-owned failures can retry by creating a fresh controller. A caller-owned
controller only exposes retry when `onRetry` is supplied; that callback must
repair or replace the external controller before it completes.

### Scrub previews

`showScrubPreview` controls the preview overlay, not seeking itself. The
built-in provider returns encoded image bytes only for the source/platform
combinations in the matrix above. `thumbnailProvider` can add authenticated,
asset, cached, or backend-specific extraction. `scrubPreviewBuilder` receives
the resulting bytes (which may be null) and the target time, and should retain
a useful time-only state when no image is available.

Preview requests are debounced, serialized, grouped into one-second cache
buckets, and given a two-second player-side wait limit. A timeout falls back to
time-only display for the rest of that drag; a new scrub interaction may try
again. Dart futures are not cancellable, so an expensive custom provider should
also bound and cancel its own underlying I/O. Late or superseded results are
ignored and never block the final seek.

### Fullscreen and closing

The package does not push routes, modify application chrome, or choose a window
for you. For controlled fullscreen, pass the current `isFullscreen` value and
handle the requested value from `onFullscreenChanged`. `onToggleFullscreen` is
available for hosts that only need a stateless toggle callback; when both are
present, `onFullscreenChanged` takes precedence. Update `isFullscreen` after
the host transition so the icon, label, and Escape behavior stay synchronized.

Provide `onClose` only in a dismissible presentation such as fullscreen, split
view, picture-in-picture, or an independent window; the close control is absent
when the callback is null. While `isFullscreen` is true and a fullscreen
callback exists, Escape requests `false` rather than closing. Otherwise Escape
invokes `onClose`, or is ignored when neither action is available. Clicking the
visible close control always invokes `onClose` directly.

### Localization and custom states

Pass `MithkaVideoPlayerLabels` for localized control, state, timeline, and error
announcements. Loading and error builders let a host match its own design while
the default views remain dependency-free. The error callback receives playback
failures for logging or recovery; do not show raw backend exception strings to
users.

## Input and accessibility contract

The player is focusable but does not need to steal focus from the surrounding
screen. Set autofocus only for a dedicated player route or child window.

| Input | Behavior |
| --- | --- |
| `Space` or `K` | Play/pause; replay after completion |
| `J` or `Left` | Seek backward by the configured interval |
| `L` or `Right` | Seek forward by the configured interval |
| `Up` / `Down` | Raise/lower volume |
| `M` | Mute/restore the last audible volume |
| `F` | Ask the host to toggle fullscreen |
| `Escape` | Exit controlled fullscreen first; otherwise close when `onClose` is present |
| Touch double-tap left or right | Seek backward/forward |
| Touch double-tap center | Play/pause |
| Mouse/trackpad double-click | Ask the host to toggle fullscreen |
| Mouse wheel over player | Adjust volume when `enableScrollVolume` is true |
| Timeline `Home` / `End` | Seek to start/end |

Controls provide button/toggled/value semantics. The timeline supports
screen-reader increase/decrease actions, keyboard focus, a visible focus ring,
and RTL-aware pointer, paint, and horizontal-key mapping. Labels localize the
control/state names; elapsed and duration values use numeric clock notation.

## Application lifecycle

Choose the lifecycle behavior based on where the player lives:

- `MithkaVideoLifecycleBehavior.pauseAndResume` for a dedicated playback
  screen;
- `MithkaVideoLifecycleBehavior.pause` without automatic resume for feeds and
  chat attachments; or
- `MithkaVideoLifecycleBehavior.delegateToController` when a higher-level media
  session owns lifecycle policy.

Automatic resume occurs only when lifecycle handling paused a video that was
already playing; it must not start a video the user had paused or resume while
the application is not foregrounded. Scrubbing preserves that intent even when
pause/seek commands complete asynchronously. `delegateToController` performs
no ordinary lifecycle-triggered pause or resume, so the host media session and
controller options own background policy. Interaction safety still prevents a
scrub operation from issuing its own resume while the app is not foregrounded.

## Independent desktop windows

Independent windows are optional and available only on Linux, macOS, and
Windows. The same facade is safe to import on Android, iOS, Fuchsia, and web;
there it performs no method-channel work, reports unsupported, and `open`
returns `null`. Each supported call can create a separately controlled window:

```dart
final windowId = await MithkaDesktopVideoWindows.instance.open(
  MithkaDesktopVideoWindowArguments(
    uri: Uri.parse('https://media.example/video.mp4'),
    title: 'Episode 4',
    width: 1920,
    height: 1080,
    muted: false,
  ),
  onClosed: releaseRetainedStream,
);
```

`open` returns after native initialization and display, returns `null` after a
recoverable failure/timeout, and invokes `onClosed` exactly once so retained
loopback streams or temporary files can be released. Use `activeWindowIds`,
`close(id)`, and `closeAll()` for host-managed lifecycle. Set `onError` to route
recoverable native-window errors into application telemetry.

Window arguments intentionally do not serialize authorization headers. For
protected media, pass a short-lived signed URL or a host-owned loopback URI and
release that resource from `onClosed`; do not put durable credentials in the
window command line.

At process startup, call `MithkaDesktopVideoWindows.initialize(arguments)` and
render a child player when it returns arguments. Wrap child content in
`MithkaDesktopVideoWindowHost`; Linux retains and reuses hidden secondary
engines, and the host keys each new encoded argument set so the previous player
and controller are disposed before a new URI is attached:

```dart
// Import dart:async for unawaited.
MithkaDesktopVideoWindowHost(
  initialArguments: childArguments,
  builder: (context, arguments) => ValueListenableBuilder<bool>(
    valueListenable: MithkaDesktopVideoWindows.currentWindowFullscreen,
    builder: (context, fullscreen, _) => MithkaVideoPlayer(
      source: MithkaVideoSource.uri(arguments.uri),
      width: arguments.width,
      height: arguments.height,
      initialMuted: arguments.muted,
      autofocus: true,
      isFullscreen: fullscreen,
      onClose: MithkaDesktopVideoWindows.closeCurrentWindow,
      onFullscreenChanged: (value) {
        unawaited(
          MithkaDesktopVideoWindows.setCurrentWindowFullscreen(value),
        );
      },
    ),
  ),
)
```

Use the desired-state `setCurrentWindowFullscreen` API instead of blindly
toggling: native title-bar actions and repeated keyboard commands can otherwise
make host and player state drift. With the wiring above, `F` and desktop
double-click request fullscreen, Escape exits fullscreen first, and a second
Escape closes the child window.

Window arguments require an absolute URI understood by the child playback
backend—normally an HTTPS or `file:` URI. They do not transport Flutter asset
keys, controller builders, HTTP headers, or controller instances across
engines. Keep those resources in host-owned infrastructure or use a
short-lived/loopback URI with `onClosed` cleanup. If the application has more
than one child-window protocol, give the arguments and `initialize` call the
same custom `windowType`.

The full main/child flow is in
[`example/lib/main.dart`](example/lib/main.dart).

### Required native runner hooks

The Dart API cannot install the native child-engine factory. Copy the relevant
integration from this package's example runner and compare it with the current
[`multi_window_manager` setup](https://pub.dev/packages/multi_window_manager):

- Linux: call `multi_window_manager_linux_init` before generated plugin
  registration, then detach Flutter's quit-on-child-close handler.
- macOS: expose generated plugin registration to secondary engines and keep the
  application alive while the main window exists.
- Windows: install `MultiWindowManagerPluginSetWindowCreatedCallback`, forward
  the child arguments into its `FlutterWindow`, and call
  `SetQuitOnClose(false)` for child windows.

Linux forces child-engine reuse and some window placement APIs require X11.
Test both X11 and Wayland if exact window placement is part of your product.

## Host platform setup

### Apple Swift Package Manager

Enable Flutter's SPM integration before resolving or building an Apple host:

```sh
flutter config --enable-swift-package-manager
flutter pub get
flutter build ios --simulator --debug
flutter build macos --debug
```

The example intentionally has no iOS or macOS Podfile and links Flutter's
generated plugin Swift package from both Xcode projects. Its native Apple
dependencies, including `fc_native_video_thumbnail` and macOS
`multi_window_manager`, provide SPM manifests.
If the optional FVP adapter is present—even when runtime configuration selects
only Windows/Linux—Flutter still discovers FVP as an Apple native plugin. Keep
the tested `third_party/fvp` override shown above or independently validate the
chosen fork's resources, binary target, and framework links under SPM. Do not
silently add a Podfile to this example; that switches the validation path back
to CocoaPods.

- Android hosts must use SDK 24 or newer for the current official playback
  backend.
- Hosts that use the built-in native scrub-thumbnail provider must target iOS
  14.0 or newer and macOS 11.0 or newer.
- Android network playback needs `<uses-permission
  android:name="android.permission.INTERNET" />` in the main manifest.
- iOS/macOS cleartext HTTP requires a narrowly scoped App Transport Security
  exception. Prefer HTTPS instead of enabling arbitrary loads.
- macOS network playback needs the `com.apple.security.network.client`
  entitlement in DebugProfile and Release.
- A sandboxed macOS app also needs an appropriate user-selected or app-container
  file entitlement for native files outside its container.
- Web does not support native file controllers. Browser autoplay can reject
  unmuted playback without a user gesture; codecs vary by browser; media hosts
  should support HTTP Range requests for reliable seeking. `mixWithOthers` is
  ignored by the web backend.
- The official `video_player` implementation does not include Windows/Linux;
  add `mithka_video_player_fvp` and call
  `MithkaFvpBackend.ensureInitialized()` before creating a controller there.
- Linux thumbnail builds require the FFmpeg development/runtime libraries for
  `libavformat`, `libavcodec`, `libavutil`, and `libswscale`, plus `libjpeg`.
  On Debian/Ubuntu install `libavformat-dev libavcodec-dev libavutil-dev
  libswscale-dev libjpeg-dev` in development and CI images.

These constraints come from Flutter's current
[`video_player` documentation](https://pub.dev/packages/video_player),
[`video_player_web` limitations](https://pub.dev/documentation/video_player_web/latest/),
and the official [Flutter video recipe](https://docs.flutter.dev/cookbook/plugins/play-video).

## Testing and validation

```sh
cd packages/mithka_video_player
flutter pub get
flutter analyze --fatal-infos
flutter test

cd ../mithka_video_player_fvp
flutter pub get
flutter analyze --fatal-infos
flutter test

cd ../mithka_video_player/example
flutter analyze --fatal-infos
flutter test
flutter build web --release
```

The path-filtered `Mithka video player` workflow also compile-smokes the example
for Android, iOS simulator, Linux, macOS, and Windows. Before release, test real
media on physical mobile devices and each target browser/OS; unit tests cannot
validate hardware decoding, codec support, audio routing, or native window
lifecycle.

## Deliberate boundaries

The package does not own application routing, DRM/license acquisition, adaptive
quality selection UI, analytics, sharing/forwarding, persistent resume storage,
system picture-in-picture, casting, or playlist policy. Build those around the
callbacks and controller ownership contract so the same player remains usable
across unrelated applications.
