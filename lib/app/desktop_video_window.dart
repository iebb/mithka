import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mithka_video_player/mithka_video_player.dart';

import '../chat/video_player_view.dart';
import '../l10n/app_localizations.dart';
import 'video_split_controller.dart';

bool get supportsDesktopVideoWindows => mithkaSupportsDesktopVideoWindows;

typedef DesktopVideoWindowArguments = MithkaDesktopVideoWindowArguments;

class DesktopVideoWindowService {
  DesktopVideoWindowService._();

  static final DesktopVideoWindowService instance =
      DesktopVideoWindowService._();

  Future<bool> open(VideoSplitSession session, {bool muted = false}) async {
    if (!supportsDesktopVideoWindows) return false;
    final stream = TdVideoStreamServer(session.video.id);
    final uri = await stream.start();
    if (uri == null) {
      await stream.close();
      return false;
    }
    try {
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
      return true;
    } catch (_) {
      await stream.close();
      return false;
    }
  }
}

class DesktopVideoWindowApp extends StatefulWidget {
  const DesktopVideoWindowApp({super.key, required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  State<DesktopVideoWindowApp> createState() => _DesktopVideoWindowAppState();
}

class _DesktopVideoWindowAppState extends State<DesktopVideoWindowApp> {
  @override
  void initState() {
    super.initState();
    unawaited(
      MithkaDesktopVideoWindows.configureCurrentWindow(
        title: widget.arguments.title,
        videoWidth: widget.arguments.width,
        videoHeight: widget.arguments.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: widget.arguments.title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: ColoredBox(
      color: Colors.black,
      child: MithkaVideoPlayer(
        source: MithkaVideoSource.uri(widget.arguments.uri),
        width: widget.arguments.width,
        height: widget.arguments.height,
        initialMuted: widget.arguments.muted,
        onClose: MithkaDesktopVideoWindows.closeCurrentWindow,
        onToggleFullscreen:
            MithkaDesktopVideoWindows.toggleCurrentWindowFullscreen,
      ),
    ),
  );
}
