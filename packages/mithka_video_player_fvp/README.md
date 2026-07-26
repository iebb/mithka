# mithka_video_player_fvp

`mithka_video_player_fvp` is the optional FVP backend adapter for
`mithka_video_player`. Add it when a host needs playback on Windows or Linux,
or deliberately chooses FVP/libmdk instead of the official `video_player`
implementation on another native platform.

Keeping this adapter separate lets applications that use only the official
Android, iOS, macOS, or web implementations avoid FVP's native binaries.

## Installation

Both packages are private to this repository:

```yaml
dependencies:
  mithka_video_player:
    path: ../mithka/packages/mithka_video_player
  mithka_video_player_fvp:
    path: ../mithka/packages/mithka_video_player_fvp

  # Keep FVP direct in final applications so its native assets are included
  # correctly on Flutter 3.27 and newer.
  fvp: ^0.37.3

# Required when reproducing this repository's tested Apple SPM builds.
dependency_overrides:
  fvp:
    path: ../mithka/third_party/fvp
```

Dependency overrides are not inherited from this adapter, so the final
application must declare the override. This repository's iOS/macOS SPM builds
use `third_party/fvp` version `0.37.3+mithka.1`, including its current privacy
resource, binary-target, and Apple framework-link fixes. A different upstream
version or fork may be valid, but it is a different native artifact and must be
verified with both iOS and macOS SPM builds.

Do not add this adapter to applications that exclusively use official
`video_player` backends. Flutter discovers transitive native plugins before
Dart tree shaking, so selecting only some platforms at runtime does not remove
FVP binaries from the other native platform builds declared by FVP.

## Initialization

Initialize the adapter before constructing any `VideoPlayerController`. Repeat
this in every Flutter engine entry point, including independent desktop-window
engines:

```dart
import 'package:flutter/widgets.dart';
import 'package:mithka_video_player_fvp/mithka_video_player_fvp.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MithkaFvpBackend.ensureInitialized();
  runApp(const MyApp());
}
```

The default configuration selects Windows and Linux. Official implementations
remain active on Android, iOS, macOS, and web.

Select other native platforms or tune documented FVP/libmdk options explicitly:

```dart
MithkaFvpBackend.ensureInitialized(
  configuration: const MithkaFvpConfiguration(
    platforms: {
      MithkaFvpPlatform.ios,
      MithkaFvpPlatform.linux,
      MithkaFvpPlatform.macos,
      MithkaFvpPlatform.windows,
    },
    videoDecoders: ['VT', 'FFmpeg'],
    maxWidth: 3840,
    maxHeight: 2160,
    lowLatency: MithkaFvpLowLatency.videoOnDemand,
  ),
);
```

The Dart registration guard is per isolate, while FVP/libmdk global settings
affect the native process. Call `ensureInitialized` in every Flutter engine
entry point with the same configuration, before any controller is created;
later calls in the same isolate are ignored. Set global/player options only
when their behavior is covered by the exact FVP and libmdk versions shipped by
the final application. On web, initialization is a safe no-op and the official
web backend remains active.

## Apple Swift Package Manager

The adapter is optional, but adding it makes FVP discoverable as a native Apple
plugin even when `platforms` selects only Linux and Windows. Runtime selection
does not remove native plugins from iOS/macOS dependency resolution.

For the repository-tested SPM path:

```sh
flutter config --enable-swift-package-manager
flutter pub get
flutter build ios --simulator --debug
flutter build macos --debug
```

Keep the application-level `third_party/fvp` override above. The
`mithka_video_player` example is intentionally Podfile-free and compile-smokes
this exact integration. If an application only uses official Apple playback
and does not build Windows/Linux, omit this adapter entirely to avoid shipping
or resolving FVP's native binaries.

### macOS MDK packaging

FVP's macOS MDK framework can contain development search paths for
`/opt/homebrew/lib` and `/usr/local/lib`. Leaving either path in the embedded
binary lets a user's Homebrew or locally installed FFmpeg load alongside MDK's
bundled FFmpeg. The duplicate Objective-C classes can then make decoder
selection depend on software installed outside the application bundle.

Every macOS host that includes this adapter must add a Runner shell-script
build phase after Flutter's framework-embed phase and before the final app
signature. Invoke the adapter's tracked helper from that phase:

```sh
/bin/bash "$SRCROOT/../packages/mithka_video_player_fvp/tool/sanitize_mdk_macos.sh"
```

Adjust the relative package path for the host repository layout. Declare the
helper and
`$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/mdk.framework/Versions/A/mdk`
as input paths. The helper removes only those two development rpaths, verifies
their absence, and re-signs `mdk.framework` with Xcode's active signing
identity before Xcode signs the finished application. The repository root host
and the buildable example contain complete phase definitions that can be used
as integration references.

## Validation

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test
```

The `mithka_video_player` example consumes this adapter and compile-smokes its
repository FVP fork across supported Flutter platforms.
