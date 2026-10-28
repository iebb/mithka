# Video playback failure reports

Search Sentry project `mithka` for `logger:mithka.video` (or exception type
`VideoPlaybackFailure`). These are handled error events, independent of the
2% transaction tracing rate. No Sentry configuration change is required.

Coverage includes the main player (fullscreen, split and in-app PiP), detached
desktop video windows, inline animations, video stickers and story videos.
Initialization and runtime failures are reported. In the main player, a report
is sent only after its existing stream, rendering-surface and completed-file
recovery paths fail. Successful recovery, normal dismissal, suspended/recycled
inline players, intentional static sticker fallback, and nonfatal player
commands are not reported as terminal playback failures.

## Diagnostic fields

- `video.platform`, `video.location`, `video.backend`, `video.view_type`,
  `video.source`, `video.stage`, `video.reason` are bounded tags.
- `video_playback` context contains the allowlisted MIME type, known pixel
  dimensions, initialization-attempt count, whether initialization ever
  succeeded, recovery flags and the last six classified failures.
- Numeric native error codes and a fixed codec vocabulary are extracted when
  available. Codec hints are parsed from errors, not a probe of the media.
- Sentry supplies release/build, OS, device model/architecture and memory
  context. `git.commit` is retained when available. Backend `android_routed`
  describes the configured platform/MDK WebM routing policy, not a verified
  hardware decoder. Other native platforms use MDK.

Raw exceptions, media URLs/paths/names, media/chat/message/account IDs, titles,
user identifiers and ambient navigation breadcrumbs are excluded. A targeted
`beforeSend` filter removes inherited private context without changing ordinary
crash reporting. Device names, device/app-specific identifiers, visible view
names and raw OS/runtime descriptions are removed while model, OS, GPU and
memory diagnostics remain available. SDK contexts use explicit field allowlists
so newly introduced context fields are not automatically transmitted.

## Volume and interpretation

One event is allowed per media selection, including subsequent manual retries.
Across selections, the same platform/location/stage/reason signature is limited
to one event per ten minutes and all signatures together to twenty events per
rolling hour **per Dart isolate**. Detached windows have separate isolates.
Failure history is bounded and successful playback emits no new telemetry.
SDK delivery errors are swallowed and never block playback.

Counts are therefore diagnostic samples, not playback failure rates or unique
user counts. Group by device model, OS version, release, reason and view type
to find compatibility clusters. Do not infer good health from no reports.
Native process crashes still rely on existing native Sentry crash reporting;
visually corrupted frames without a player error cannot be detected here.

Detached video windows initialize their own Dart hub with native SDK
initialization, native scope synchronization, session tracking and automatic
performance tracing disabled. Only explicit video reports are accepted there;
the main window remains responsible for process-wide crash/tracing settings.

## Verification

Run `flutter test test/video_playback_reporting_test.dart
test/mobile_fullscreen_video_player_widget_test.dart`.
Tests use an in-memory capture sink and do not send synthetic production events.
After shipping a Sentry-enabled build, verify real reports under
`logger:mithka.video` before drawing device-level conclusions. Keep the existing
2% tracing rate until transaction access and data volume can be assessed.
