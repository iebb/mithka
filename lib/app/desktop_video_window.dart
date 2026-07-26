import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import '../chat/video_player_view.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import 'video_split_controller.dart';

const _desktopVideoWindowType = 'mithka.video';

bool get supportsDesktopVideoWindows =>
    !Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia;

class DesktopVideoWindowArguments {
  const DesktopVideoWindowArguments({
    required this.uri,
    required this.title,
    required this.width,
    required this.height,
    required this.muted,
  });

  final Uri uri;
  final String title;
  final int? width;
  final int? height;
  final bool muted;

  String encode() => jsonEncode({
    'type': _desktopVideoWindowType,
    'uri': uri.toString(),
    'title': title,
    'width': width,
    'height': height,
    'muted': muted,
  });

  static DesktopVideoWindowArguments? tryParse(String source) {
    if (source.isEmpty) return null;
    try {
      final value = jsonDecode(source);
      if (value is! Map || value['type'] != _desktopVideoWindowType) {
        return null;
      }
      final uri = Uri.tryParse(value['uri'] as String? ?? '');
      if (uri == null || !uri.hasScheme) return null;
      return DesktopVideoWindowArguments(
        uri: uri,
        title: value['title'] as String? ?? 'Video',
        width: value['width'] as int?,
        height: value['height'] as int?,
        muted: value['muted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class DesktopVideoWindowService with WindowListener {
  DesktopVideoWindowService._();

  static final DesktopVideoWindowService instance =
      DesktopVideoWindowService._();

  final Map<int, TdVideoStreamServer> _streams = {};
  bool _observesWindowChanges = false;

  Future<bool> open(VideoSplitSession session, {bool muted = false}) async {
    if (!supportsDesktopVideoWindows) return false;
    final stream = TdVideoStreamServer(session.video.id);
    final uri = await stream.start();
    if (uri == null) {
      await stream.close();
      return false;
    }
    try {
      final controller = await MultiWindowManager.createWindow([
        DesktopVideoWindowArguments(
          uri: uri,
          title: session.title,
          width: session.width,
          height: session.height,
          muted: muted,
        ).encode(),
      ]);
      if (controller == null) throw StateError('Window creation failed');
      _streams[controller.id] = stream;
      if (!_observesWindowChanges) {
        _observesWindowChanges = true;
        MultiWindowManager.addGlobalListener(this);
      }
      await controller.show();
      return true;
    } catch (_) {
      await stream.close();
      return false;
    }
  }

  @override
  void onWindowClose([int? windowId]) {
    if (windowId != null) unawaited(_streams.remove(windowId)?.close());
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
    unawaited(_configureWindow());
  }

  Future<void> _configureWindow() async {
    final windowManager = MultiWindowManager.current;
    final width = widget.arguments.width;
    final height = widget.arguments.height;
    final aspect = width != null && height != null && width > 0 && height > 0
        ? width / height
        : 16 / 9;
    const preferredWidth = 880.0;
    final preferredHeight = (preferredWidth / aspect).clamp(420.0, 720.0);
    await windowManager.setMinimumSize(const Size(420, 280));
    await windowManager.setSize(Size(preferredWidth, preferredHeight));
    await windowManager.setTitle(widget.arguments.title);
    await windowManager.center();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        child: VideoPlayerView(
          video: TdFileRef(id: 0),
          width: widget.arguments.width,
          height: widget.arguments.height,
          directSourceUri: widget.arguments.uri,
          initialMuted: widget.arguments.muted,
          onClose: MultiWindowManager.current.close,
          onToggleFullscreen: _toggleFullscreen,
        ),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    final window = MultiWindowManager.current;
    await window.setFullScreen(!await window.isFullScreen());
  }
}
