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
  testWidgets(
    'narrow desktop video chrome starts the bottom row with play, without empty queue slots',
    (tester) async {
      tester.view.physicalSize = const Size(560, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = FVideoChromeScope(
        snapshot: const FVideoChromeSnapshot(
          value: VideoPlayerValue(
            duration: Duration(minutes: 2),
            size: Size(1080, 1920),
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
          home: MithkaDesktopVideoChrome(
            scope: scope,
            title: 'Demo Clip',
            inspectorVisible: false,
            onToggleInspector: () {},
            aspectRatio: 9 / 16,
            thumbnailProvider: (_) async => null,
          ),
        ),
      );
      await tester.pump();

      Rect lowest(Finder finder) => finder
          .evaluate()
          .map((element) {
            final box = element.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) & box.size;
          })
          .reduce((a, b) => a.top >= b.top ? a : b);

      final play = lowest(find.bySemanticsLabel('Play'));
      final mute = lowest(find.bySemanticsLabel('Mute'));
      // The bottom bar is inset 14 from the window edge at this width.
      expect(play.left, moreOrLessEquals(14, epsilon: 0.5));
      expect(mute.left - play.right, moreOrLessEquals(4, epsilon: 0.5));
      expect(find.bySemanticsLabel('Playback speed'), findsOneWidget);
    },
  );

  testWidgets('share button opens one menu with Save as and Share', (
    tester,
  ) async {
    var saves = 0;
    var shares = 0;
    var opened = 0;
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

    Future<void> pump({required bool canShare}) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MithkaDesktopVideoChrome(
          scope: scope,
          title: 'Demo Clip',
          inspectorVisible: false,
          onToggleInspector: () {},
          aspectRatio: 16 / 9,
          thumbnailProvider: (_) async => null,
          shareButton: MithkaVideoShareMenuButton(
            controlsVisible: true,
            onSave: () => saves++,
            onShare: canShare ? () => shares++ : null,
            onOpened: () => opened++,
          ),
        ),
      ),
    );

    await pump(canShare: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MithkaDesktopVideoChrome)),
    );
    final saveAs = find.text(l10n.t(AppStringKeys.messageActionSaveAs));
    final share = find.text(l10n.t(AppStringKeys.topicChatShare));
    final button = find.byKey(const ValueKey('video-window-share-button'));
    final menu = find.byKey(const ValueKey('video-window-share-menu'));

    expect(menu, findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(saveAs, findsOneWidget);
    expect(share, findsOneWidget);
    // The menu hangs below the button, aligned to its trailing edge.
    expect(
      tester.getTopRight(menu).dx,
      moreOrLessEquals(tester.getTopRight(button).dx, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(menu).dy,
      greaterThan(tester.getBottomLeft(button).dy),
    );

    await tester.tap(saveAs);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(menu, findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(shares, 1);
    expect(menu, findsNothing);

    // Tapping outside closes it without running anything.
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect((saves, shares), (1, 1));

    // Without a chat to forward from, only Save as is offered.
    await pump(canShare: false);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saveAs, findsOneWidget);
    expect(share, findsNothing);
  });
}
