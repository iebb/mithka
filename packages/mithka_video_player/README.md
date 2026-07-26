# mithka_video_player

A reusable Flutter video player with responsive phone, tablet, and desktop
controls. The package deliberately keeps application-specific streaming,
forwarding, and navigation outside the player.

Features:

- network, local-file, and asset sources;
- play/pause, mute, volume, playback speed, buffered progress, and fullscreen;
- keyboard controls (`Space`/`K`, `J`/`L`, arrow keys, `M`, `F`, `Escape`);
- double-click/tap seeking and scrub thumbnails;
- larger controls and an inline volume slider on wide tablet/desktop layouts;
- multiple independent macOS, Windows, and Linux video windows;
- custom-painted controls, with no Material or Cupertino icon dependency.

## Embedded player

```dart
MithkaVideoPlayer(
  source: MithkaVideoSource.network(videoUrl),
  width: 1920,
  height: 1080,
  onToggleFullscreen: toggleFullscreen,
)
```

## Independent desktop windows

Call `MithkaDesktopVideoWindows.initialize(arguments)` before starting the
primary app. If it returns arguments, start a child-window app containing a
`MithkaVideoPlayer`. The complete primary/child flow is in `example/lib/main.dart`.

The native runner still needs the setup required by `multi_window_manager`.
Mithka's macOS, Windows, and Linux runners are working reference integrations.
