## 0.3.0

- Added an immutable custom-chrome scope with playback snapshots, localized
  labels, optional previous/next navigation, and a controller-safe actions
  facade for play, seek, scrub, volume, speed, visibility, and fullscreen.
- Added `MithkaVideoInteractionMode.delegateToChrome` so project-owned mobile
  gestures can exclusively own surface taps and drags while the package keeps
  the video surface, buffering, captions, focus, keyboard, and state updates.
- Added accessible, custom-painted previous/play/next transport controls to the
  default chrome whenever host navigation callbacks are supplied.
- Made fullscreen default controls and captions honor top, bottom, and
  horizontal safe-area insets without changing embedded spacing.
- Rendered already-initialized caller-owned controllers immediately while
  applying changed initial settings asynchronously as nonfatal commands.
- Merged center transport into the bottom row below 220 logical pixels high,
  preventing compact 16:9 chrome from painting controls over each other.
- Expanded the example and tests to cover custom chrome, navigation callbacks,
  gesture delegation, and caller-owned controller lifetime.

## 0.2.0

- Moved FVP initialization and typed backend configuration into the optional
  `mithka_video_player_fvp` adapter so official-backend applications do not
  inherit FVP native binaries.
- Made source and thumbnail creation web-safe, including a clear unsupported
  file-source contract, injectable providers, and graceful thumbnail fallback.
- Replaced the mobile-only thumbnail dependency with
  `fc_native_video_thumbnail` for Android, iOS, Linux, macOS, and Windows,
  including Swift Package Manager compatibility.
- Added network headers, caption sources, controller options, custom controller
  builders, and value equality to video source descriptions.
- Added caller-vs-player controller ownership rules and hardened controller
  replacement, initialization, listener cleanup, and disposal.
- Added configurable lifecycle behavior, focus, seek interval, controls timeout,
  fit/alignment, captions, fullscreen state, loading/error builders, and richer
  playback/error callbacks.
- Reworked controls and state views without Material/Cupertino dependencies;
  improved keyboard, pointer-wheel, touch, focus, and semantics behavior.
- Prevented premature/looping completion, preserved play intent across delayed
  scrub commands and lifecycle transitions, and made controller replacement
  cancel in-flight scrub/thumbnail state deterministically.
- Made controls focus- and accessible-navigation-aware, excluded hidden chrome
  from focus/semantics, resolved mouse-wheel ownership correctly, and prevented
  narrow/high-text-scale control overflow.
- Debounced, serialized, cached, and timeout-bounded scrub thumbnails; ignored
  stale results and sized previews from the effective video aspect ratio.
- Added keyboard/screen-reader-adjustable and RTL-aware timeline behavior with
  visible focus indication and accumulated key-repeat input.
- Hardened independent desktop windows with versioned/sanitized arguments,
  concurrent lifecycle tracking, startup timeout/error reporting, close/closeAll,
  and safe no-op implementations on unsupported platforms.
- Added a six-platform example covering package-owned and injected controllers,
  network/asset/file sources, fullscreen, callbacks, and multiple independent
  desktop windows.
- Added deterministic source, window, thumbnail, slider, design-policy, adapter,
  and example tests plus path-filtered cross-platform CI compile smoke coverage.

## 0.1.0

- Initial standalone responsive player.
- Added reusable timeline and thumbnail helpers.
- Added independent desktop video-window lifecycle support.
