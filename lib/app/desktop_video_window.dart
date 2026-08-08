import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

import '../chat/video_player_view.dart';
import '../l10n/app_localizations.dart';
import 'desktop_media_window_registry.dart';
import 'video_split_controller.dart';

bool get supportsDesktopVideoWindows => mithkaSupportsDesktopVideoWindows;

typedef DesktopVideoWindowArguments = MithkaDesktopVideoWindowArguments;

@visibleForTesting
Future<bool> prepareDesktopVideoPlayback(
  Future<bool> Function() prepare, {
  int maximumAttempts = 2,
}) async {
  assert(maximumAttempts > 0);
  for (var attempt = 0; attempt < maximumAttempts; attempt++) {
    if (await prepare()) return true;
  }
  return false;
}

class DesktopVideoWindowService {
  DesktopVideoWindowService._();

  static final DesktopVideoWindowService instance =
      DesktopVideoWindowService._();

  /// Keeps one window per video: a repeat play raises the window that already
  /// has it instead of stacking a second copy of the same video.
  final DesktopMediaWindowRegistry _windows = DesktopMediaWindowRegistry();

  Future<bool> open(VideoSplitSession session, {bool muted = false}) async {
    if (!supportsDesktopVideoWindows) return false;
    final videoId = session.video.id;
    if (_windows.isOpening(videoId)) return true;
    final existing = _windows.windowFor(videoId);
    if (existing != null) {
      if (await MithkaDesktopVideoWindows.instance.focus(existing)) return true;
      _windows.forget(videoId);
    }
    _windows.beginOpening(videoId);
    final stream = TdVideoStreamServer(videoId);
    var handedOffToWindow = false;
    int? openedWindowId;
    try {
      final uri = await stream.start();
      if (uri == null) return false;
      // Binding the loopback server is quick; filling its bootstrap ranges is
      // not. Start that in the background and open the window immediately so
      // the player's own loading state stands in for the wait — waiting here
      // would leave the chat looking like the tap did nothing.
      stream.holdRequestsUntilPrepared(
        prepareDesktopVideoPlayback(stream.prepareForPlayback),
      );
      final windowId = await MithkaDesktopVideoWindows.instance.open(
        DesktopVideoWindowArguments(
          uri: uri,
          title: session.title,
          width: session.width,
          height: session.height,
          muted: muted,
        ),
        onClosed: () {
          _windows.forget(videoId);
          return stream.close();
        },
      );
      if (windowId == null) throw StateError('Window creation failed');
      openedWindowId = windowId;
      handedOffToWindow = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _windows.finishOpening(videoId, windowId: openedWindowId);
      if (!handedOffToWindow) await stream.close();
    }
  }
}

class DesktopVideoWindowApp extends StatelessWidget {
  const DesktopVideoWindowApp({super.key, required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: arguments.title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: MithkaDesktopVideoWindowHost(
      initialArguments: arguments,
      builder: (context, arguments) =>
          _DesktopVideoWindowPlayer(arguments: arguments),
    ),
  );
}

class _DesktopVideoWindowPlayer extends StatelessWidget {
  const _DesktopVideoWindowPlayer({required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: MithkaDesktopVideoWindows.currentWindowFullscreen,
    builder: (context, fullscreen, _) => ColoredBox(
      color: Colors.black,
      child: MithkaVideoPlayer(
        source: MithkaVideoSource.uri(arguments.uri),
        width: arguments.width,
        height: arguments.height,
        initialMuted: arguments.muted,
        autofocus: true,
        isFullscreen: fullscreen,
        onFullscreenChanged: (value) => unawaited(
          MithkaDesktopVideoWindows.setCurrentWindowFullscreen(value),
        ),
      ),
    ),
  );
}
