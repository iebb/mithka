import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

import '../chat/video_player_view.dart';
import '../l10n/app_localizations.dart';
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

  Future<bool> open(VideoSplitSession session, {bool muted = false}) async {
    if (!supportsDesktopVideoWindows) return false;
    final stream = TdVideoStreamServer(session.video.id);
    var handedOffToWindow = false;
    try {
      final uri = await stream.start();
      if (uri == null) return false;
      final prepared = await prepareDesktopVideoPlayback(
        stream.prepareForPlayback,
      );
      if (!prepared) return false;
      final windowId = await MithkaDesktopVideoWindows.instance.open(
        DesktopVideoWindowArguments(
          uri: uri,
          title: session.title,
          width: session.width,
          height: session.height,
          muted: muted,
        ),
        onClosed: stream.close,
      );
      if (windowId == null) throw StateError('Window creation failed');
      handedOffToWindow = true;
      return true;
    } catch (_) {
      return false;
    } finally {
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
