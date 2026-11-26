import 'dart:typed_data';

import 'package:cineplay/cineplay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media/video_player_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

class _NoopVideoActions implements FVideoActions {
  @override
  void beginScrub(double fraction) {}

  @override
  Future<Uint8List?> captureFrame({int? width, int? height}) async => null;

  @override
  Future<void> endScrub(double fraction) async {}

  @override
  void hideControls() {}

  @override
  Future<void> nextChapter() async {}

  @override
  Future<void> previousChapter() async {}

  @override
  Future<void> requestPictureInPicture(bool pictureInPicture) async {}

  @override
  void requestFullscreen(bool fullscreen) {}

  @override
  void rotateClockwise() {}

  @override
  Future<void> seekBy(Duration delta) async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> seekToChapter(FVideoChapter chapter) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  void setRotationQuarterTurns(int quarterTurns) {}

  @override
  void setFit(BoxFit fit) {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  void showControls() {}

  @override
  Future<void> stepFrames(int frames) async {}

  @override
  void toggleControls() {}

  @override
  void toggleFit() {}

  @override
  Future<void> toggleLooping() async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> togglePlayback() async {}

  @override
  void updateScrub(double fraction) {}
}

void main() {
  testWidgets(
    'desktop video chrome omits top-left close button and uses shadowed icons without circles',
    (tester) async {
      final scope = FVideoChromeScope(
        snapshot: const FVideoChromeSnapshot(
          value: VideoPlayerValue(
            duration: Duration(minutes: 2),
            size: Size(1920, 1080),
            isInitialized: true,
          ),
          playbackState: FVideoPlaybackState.paused,
          displayPosition: Duration.zero,
          controlsVisible: true,
          isScrubbing: false,
          bufferingIndicatorVisible: false,
          isFullscreen: false,
        ),
        actions: _NoopVideoActions(),
        labels: const FVideoPlayerLabels(),
        previous: null,
        next: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            width: 800,
            height: 600,
            child: MithkaDesktopVideoChrome(
              scope: scope,
              title: 'Demo Clip',
              onClose: () {},
              inspectorVisible: false,
              onToggleInspector: () {},
              aspectRatio: 16 / 9,
              thumbnailProvider: (_) async => null,
              pinButton: MithkaVideoChromeAction(
                icon: HeroAppIcons.pin,
                label: 'Pin window on top',
                onTap: () {},
              ),
              fullscreenButton: MithkaVideoChromeAction(
                icon: HeroAppIcons.expand,
                label: 'Fullscreen',
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Close'), findsNothing);
      final circularDecorations = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(circularDecorations, findsNothing);

      final shadowedIcons = find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.shadows != null &&
            widget.shadows!.isNotEmpty,
      );
      expect(shadowedIcons, findsAtLeastNWidgets(4));

      final shadowedSeekIcons = find.byWidgetPredicate(
        (widget) =>
            widget is AppSeekTenIcon &&
            widget.shadows != null &&
            widget.shadows!.isNotEmpty,
      );
      expect(shadowedSeekIcons, findsNWidgets(2));
    },
  );
}
