import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:video_player/video_player.dart';

import '../chat/video_player_view.dart';
import '../l10n/app_localizations.dart';
import '../platform/system_picture_in_picture.dart';
import '../tdlib/td_client.dart';
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
    final accountSlot = session.accountSlot ?? TdClient.shared.activeSlot;
    final mediaKey = (accountSlot: accountSlot, videoId: videoId);
    if (_windows.isOpening(mediaKey)) return true;
    final existing = _windows.windowFor(mediaKey);
    if (existing != null) {
      if (await MithkaDesktopVideoWindows.instance.focus(existing)) return true;
      _windows.forget(mediaKey);
    }
    _windows.beginOpening(mediaKey);
    final accountLease = TdClient.shared.retainAccountSlot(accountSlot);
    if (accountLease == null) {
      _windows.finishOpening(mediaKey);
      return false;
    }
    final stream = TdVideoStreamServer(
      videoId,
      query: accountLease.query,
      fileName: session.video.fileName,
      mimeType: session.video.mimeType,
    );
    Future<void> releaseResources() async {
      await stream.close();
      await accountLease.release();
    }

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
          _windows.forget(mediaKey);
          return releaseResources();
        },
      );
      if (windowId == null) throw StateError('Window creation failed');
      openedWindowId = windowId;
      handedOffToWindow = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _windows.finishOpening(mediaKey, windowId: openedWindowId);
      if (!handedOffToWindow) await releaseResources();
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

class _DesktopVideoWindowPlayer extends StatefulWidget {
  const _DesktopVideoWindowPlayer({required this.arguments});

  final DesktopVideoWindowArguments arguments;

  @override
  State<_DesktopVideoWindowPlayer> createState() =>
      _DesktopVideoWindowPlayerState();
}

class _DesktopVideoWindowPlayerState extends State<_DesktopVideoWindowPlayer> {
  VideoPlayerController? _controller;
  bool _pictureInPictureSupported = false;
  bool _pictureInPicture = false;
  bool _pictureInPictureBusy = false;
  bool _pictureInPictureRestoreRequested = false;
  bool _wasPlayingBeforePictureInPicture = false;

  DesktopVideoWindowArguments get arguments => widget.arguments;

  @override
  void initState() {
    super.initState();
    MithkaDesktopVideoWindows.currentWindowCloseRevision.addListener(
      _handleWindowClosing,
    );
    unawaited(_loadPictureInPictureSupport());
  }

  Future<void> _loadPictureInPictureSupport() async {
    if (!Platform.isMacOS) return;
    final supported = await SystemPictureInPicture.isSupported();
    if (mounted && supported != _pictureInPictureSupported) {
      setState(() => _pictureInPictureSupported = supported);
    }
  }

  void _handleWindowClosing() {
    unawaited(_controller?.pause());
    if (_pictureInPicture) unawaited(SystemPictureInPicture.stop());
  }

  Future<void> _setPictureInPicture(bool enabled) async {
    if (_pictureInPictureBusy || enabled == _pictureInPicture) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _pictureInPictureBusy = true);
    if (!enabled) {
      await SystemPictureInPicture.stop();
      if (mounted) setState(() => _pictureInPictureBusy = false);
      return;
    }

    final value = controller.value;
    _pictureInPictureRestoreRequested = false;
    _wasPlayingBeforePictureInPicture = value.isPlaying;
    final sourceSize = value.size;
    final videoSize = sourceSize.width > 0 && sourceSize.height > 0
        ? sourceSize
        : Size(
            (arguments.width ?? 16).toDouble(),
            (arguments.height ?? 9).toDouble(),
          );
    final id = 'desktop-video:${arguments.uri}';
    final started = await SystemPictureInPicture.start(
      id: id,
      uri: arguments.uri,
      position: value.position,
      speed: value.playbackSpeed,
      muted: value.volume <= 0.001,
      playing: value.isPlaying,
      videoSize: videoSize,
      onRestoreRequested: (_) async {
        _pictureInPictureRestoreRequested = true;
        await MithkaDesktopVideoWindows.focusCurrentWindow();
        return true;
      },
      onStop: (finalPosition) async {
        final activeController = _controller;
        if (activeController != null && finalPosition != null) {
          await activeController.seekTo(finalPosition);
        }
        final restoreRequested = _pictureInPictureRestoreRequested;
        _pictureInPictureRestoreRequested = false;
        if (mounted) {
          setState(() {
            _pictureInPicture = false;
            _pictureInPictureBusy = false;
          });
        }
        if (restoreRequested) {
          if (_wasPlayingBeforePictureInPicture) {
            await activeController?.play();
          }
        } else {
          await MithkaDesktopVideoWindows.closeCurrentWindow();
        }
      },
    );
    if (!mounted) {
      if (started) await SystemPictureInPicture.stop();
      return;
    }
    if (started) {
      await controller.pause();
    }
    setState(() {
      _pictureInPicture = started;
      _pictureInPictureBusy = false;
    });
    if (started) await MithkaDesktopVideoWindows.hideCurrentWindow();
  }

  @override
  void dispose() {
    MithkaDesktopVideoWindows.currentWindowCloseRevision.removeListener(
      _handleWindowClosing,
    );
    unawaited(_controller?.pause());
    if (_pictureInPicture) unawaited(SystemPictureInPicture.stop());
    _controller = null;
    super.dispose();
  }

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
        onReady: (controller) => _controller = controller,
        isFullscreen: fullscreen,
        isPictureInPicture: _pictureInPicture,
        onPictureInPictureChanged: _pictureInPictureSupported
            ? _setPictureInPicture
            : null,
        onFullscreenChanged: (value) => unawaited(
          MithkaDesktopVideoWindows.setCurrentWindowFullscreen(value),
        ),
      ),
    ),
  );
}
