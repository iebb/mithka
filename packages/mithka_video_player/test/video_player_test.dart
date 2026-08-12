import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka_video_player/mithka_video_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('configures but never disposes a caller-owned controller', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final states = <MithkaVideoPlaybackState>[];
    VideoPlayerController? readyController;

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('owned'),
          controller: controller,
          autoplay: false,
          looping: true,
          initialVolume: 0.4,
          initialPlaybackSpeed: 1.25,
          initialPosition: const Duration(seconds: 15),
          onReady: (value) => readyController = value,
          onPlaybackStateChanged: states.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(readyController, same(controller));
    expect(controller.initializeCalls, 1);
    expect(controller.value.isLooping, isTrue);
    expect(controller.value.volume, 0.4);
    expect(controller.value.playbackSpeed, 1.25);
    expect(controller.value.position, const Duration(seconds: 15));
    expect(states, contains(MithkaVideoPlaybackState.paused));
    expect(find.byType(MithkaVideoSlider), findsNWidgets(2));

    final playerButtons = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_PlayerControlButton',
    );
    await tester.tap(playerButtons.first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.playCalls, 1);
    expect(states.last, MithkaVideoPlaybackState.playing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposed, isFalse);
    await controller.dispose();
  });

  testWidgets(
    'already-initialized caller controller renders before configuration',
    (tester) async {
      final controller = _FakeVideoPlayerController(initialized: true);
      controller.setLoopingGate = Completer<void>();
      final surfaceKey = GlobalKey();
      var readyCalls = 0;

      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('already-ready'),
            controller: controller,
            autoplay: false,
            looping: true,
            videoSurfaceBuilder: (context, value) =>
                SizedBox.expand(key: surfaceKey),
            onReady: (_) => readyCalls++,
          ),
        ),
      );

      expect(find.byKey(surfaceKey), findsOneWidget);
      expect(_semanticsWidget('Loading video'), findsNothing);
      expect(controller.initializeCalls, 0);
      expect(controller.setLoopingCalls, 1);
      expect(readyCalls, 1);

      controller.setLoopingGate!.complete();
      await tester.pumpAndSettle();
      expect(controller.value.isLooping, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.disposed, isFalse);
      await controller.dispose();
    },
  );

  testWidgets('post-initialization configuration errors stay nonfatal', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController(
      initialized: true,
      setLoopingError: StateError('configuration rejected'),
    );
    final errors = <MithkaVideoPlayerError>[];
    final states = <MithkaVideoPlaybackState>[];
    const surfaceKey = ValueKey('configured-surface');

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('nonfatal-configuration'),
          controller: controller,
          autoplay: false,
          looping: true,
          videoSurfaceBuilder: (context, value) =>
              const SizedBox.expand(key: surfaceKey),
          onError: errors.add,
          onPlaybackStateChanged: states.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(surfaceKey), findsOneWidget);
    expect(find.text('This video could not be played'), findsNothing);
    expect(errors, hasLength(1));
    expect(states, isNot(contains(MithkaVideoPlaybackState.failed)));
    expect(controller.disposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('default chrome renders localized previous and next controls', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    var previousCalls = 0;
    var nextCalls = 0;

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('navigation'),
          controller: controller,
          autoplay: false,
          labels: const MithkaVideoPlayerLabels(
            previous: 'Previous episode',
            next: 'Next episode',
          ),
          onPrevious: () => previousCalls++,
          onNext: () => nextCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_semanticsWidget('Previous episode'), findsOneWidget);
    expect(_semanticsWidget('Next episode'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    tester.semantics.tap(find.semantics.byLabel('Previous episode'));
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('Next episode'));
    await tester.pump();
    expect(previousCalls, 1);
    expect(nextCalls, 1);
    semantics.dispose();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposed, isFalse);
    await controller.dispose();
  });

  testWidgets(
    'fullscreen chrome respects safe areas without changing embedded',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      const padding = EdgeInsets.fromLTRB(7, 24, 9, 34);

      Widget player({required bool fullscreen}) => _frame(
        MithkaVideoPlayer(
          key: const ValueKey('safe-area-player'),
          source: _source('safe-area'),
          controller: controller,
          autoplay: false,
          isFullscreen: fullscreen,
          onClose: () {},
          onFullscreenChanged: (_) {},
        ),
        width: 500,
        height: 300,
        padding: padding,
      );

      await tester.pumpWidget(player(fullscreen: true));
      await tester.pumpAndSettle();
      var playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
      var closeRect = tester.getRect(_semanticsWidget('Close'));
      var fullscreenRect = tester.getRect(_semanticsWidget('Exit fullscreen'));
      expect(closeRect.top - playerRect.top, closeTo(14 + padding.top, 0.01));
      expect(
        playerRect.bottom - fullscreenRect.bottom,
        closeTo(12 + padding.bottom, 0.01),
      );

      await tester.pumpWidget(player(fullscreen: false));
      await tester.pump();
      playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
      closeRect = tester.getRect(_semanticsWidget('Close'));
      fullscreenRect = tester.getRect(_semanticsWidget('Fullscreen'));
      expect(closeRect.top - playerRect.top, closeTo(14, 0.01));
      expect(playerRect.bottom - fullscreenRect.bottom, closeTo(12, 0.01));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.disposed, isFalse);
      await controller.dispose();
    },
  );

  testWidgets(
    'top trailing actions respect safe areas, logical direction, focus, and semantics',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _FakeVideoPlayerController();
      final actionFocus = FocusNode(debugLabel: 'test video actions');
      addTearDown(actionFocus.dispose);
      const actionKey = ValueKey('top-trailing-action');
      const menuKey = ValueKey('top-trailing-menu');
      const padding = EdgeInsets.fromLTRB(7, 59, 9, 34);
      var actionCalls = 0;

      Widget player(TextDirection direction) => _frame(
        MithkaVideoPlayer(
          key: const ValueKey('top-trailing-player'),
          source: _source('top-trailing'),
          controller: controller,
          autoplay: false,
          isFullscreen: true,
          controlsAutoHideDuration: const Duration(milliseconds: 80),
          onClose: () {},
          topTrailingBuilder: (context, scope) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                button: true,
                label: 'More video actions',
                onTap: () => actionCalls++,
                child: Focus(
                  focusNode: actionFocus,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => actionCalls++,
                    child: const SizedBox.square(key: actionKey, dimension: 44),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(key: menuKey, width: 180, height: 90),
            ],
          ),
        ),
        width: 390,
        height: 844,
        padding: padding,
        textDirection: direction,
      );

      await tester.pumpWidget(player(TextDirection.ltr));
      await tester.pumpAndSettle();
      var playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
      var actionRect = tester.getRect(find.byKey(actionKey));
      var menuRect = tester.getRect(find.byKey(menuKey));
      expect(actionRect.top - playerRect.top, closeTo(14 + padding.top, 0.01));
      expect(
        playerRect.right - actionRect.right,
        closeTo(14 + padding.right, 0.01),
      );
      expect(playerRect.contains(menuRect.bottomRight), isTrue);
      expect(_semanticsWidget('More video actions'), findsOneWidget);
      expect(find.byType(Overlay), findsNothing);

      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('More video actions'));
      await tester.pump();
      expect(actionCalls, 1);

      actionFocus.requestFocus();
      await tester.pump();
      expect(actionFocus.hasFocus, isTrue);
      await controller.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(_controlOpacity(tester), 1);

      actionFocus.unfocus();
      await tester.pumpWidget(player(TextDirection.rtl));
      await tester.pump();
      playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
      actionRect = tester.getRect(find.byKey(actionKey));
      menuRect = tester.getRect(find.byKey(menuKey));
      final closeRect = tester.getRect(_semanticsWidget('Close'));
      expect(
        actionRect.left - playerRect.left,
        closeTo(14 + padding.left, 0.01),
      );
      expect(
        playerRect.right - closeRect.right,
        closeTo(14 + padding.right, 0.01),
      );
      expect(menuRect.right, lessThan(closeRect.left));
      expect(tester.takeException(), isNull);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    },
  );

  testWidgets('default transport style is high contrast and configurable', (
    tester,
  ) async {
    const defaults = MithkaVideoChromeStyle();
    expect(defaults.transportBackgroundColor.a, greaterThanOrEqualTo(0.8));
    expect(
      defaults.primaryTransportBackgroundColor.a,
      greaterThanOrEqualTo(0.9),
    );
    expect(defaults.transportBorderColor.a, greaterThanOrEqualTo(0.35));
    expect(defaults.foregroundColor.computeLuminance(), greaterThan(0.9));
    expect(defaults.transportBackgroundColor.computeLuminance(), lessThan(0.1));

    final controller = _FakeVideoPlayerController();
    const transport = Color(0xFF102030);
    const primary = Color(0xFF304050);
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('custom-transport-style'),
          controller: controller,
          autoplay: false,
          onPrevious: () {},
          onNext: () {},
          chromeStyle: const MithkaVideoChromeStyle(
            transportBackgroundColor: transport,
            primaryTransportBackgroundColor: primary,
            wideTransportButtonSize: 60,
            widePrimaryTransportButtonSize: 80,
            wideTransportSpacing: 17,
          ),
        ),
        width: 720,
        height: 600,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(_semanticsWidget('Previous video')),
      const Size.square(60),
    );
    expect(
      _semanticsWidget('Play')
          .evaluate()
          .map(
            (element) => tester.getSize(
              find.byElementPredicate((value) => value == element),
            ),
          )
          .toList(),
      contains(const Size.square(80)),
    );
    final circularDecorations = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    final colors = circularDecorations
        .evaluate()
        .map((element) => (element.widget as Container).decoration)
        .cast<BoxDecoration>()
        .map((decoration) => decoration.color)
        .toList();
    expect(colors, contains(transport));
    expect(colors, contains(primary));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('full custom chrome suppresses the default top trailing slot', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    var topTrailingBuilds = 0;
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('top-trailing-with-custom-chrome'),
          controller: controller,
          autoplay: false,
          chromeBuilder: (context, scope) =>
              const SizedBox.expand(key: ValueKey('replacement-chrome')),
          topTrailingBuilder: (context, scope) {
            topTrailingBuilds++;
            return const SizedBox.square(dimension: 44);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('replacement-chrome')), findsOneWidget);
    expect(topTrailingBuilds, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets(
    'portrait fullscreen gives surface final bounds and chrome viewport bounds',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402.6, 875.2);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _FakeVideoPlayerController(
        videoSize: const Size(1920, 1080),
      );
      final surfaceKey = GlobalKey();
      BoxConstraints? surfaceConstraints;
      BoxConstraints? chromeConstraints;

      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('portrait-fullscreen-geometry'),
            controller: controller,
            width: 1920,
            height: 1080,
            autoplay: false,
            isFullscreen: true,
            alignment: const Alignment(0, -0.2),
            interactionMode: MithkaVideoInteractionMode.delegateToChrome,
            videoSurfaceBuilder: (context, value) => LayoutBuilder(
              builder: (context, constraints) {
                surfaceConstraints = constraints;
                return SizedBox.expand(key: surfaceKey);
              },
            ),
            chromeBuilder: (context, scope) => LayoutBuilder(
              builder: (context, constraints) {
                chromeConstraints = constraints;
                return const SizedBox.expand();
              },
            ),
          ),
          width: 402.6,
          height: 875.2,
          padding: const EdgeInsets.fromLTRB(0, 62, 0, 34),
        ),
      );
      await tester.pumpAndSettle();

      final expectedHeight = 402.6 * 9 / 16;
      expect(surfaceConstraints, isNotNull);
      expect(surfaceConstraints!.isTight, isTrue);
      expect(surfaceConstraints!.maxWidth, closeTo(402.6, 0.01));
      expect(surfaceConstraints!.maxHeight, closeTo(expectedHeight, 0.01));
      expect(chromeConstraints, isNotNull);
      expect(chromeConstraints!.isTight, isTrue);
      expect(chromeConstraints!.biggest, const Size(402.6, 875.2));

      final playerRect = tester.getRect(find.byType(MithkaVideoPlayer));
      final surfaceRect = tester.getRect(find.byKey(surfaceKey));
      expect(surfaceRect.width, closeTo(playerRect.width, 0.01));
      expect(surfaceRect.height, closeTo(expectedHeight, 0.01));
      expect(
        surfaceRect.top - playerRect.top,
        closeTo((playerRect.height - expectedHeight) * 0.4, 0.01),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    },
  );

  testWidgets('surface sizing preserves every BoxFit mode', (tester) async {
    final controller = _FakeVideoPlayerController(
      videoSize: const Size(200, 100),
    );
    const expected = <BoxFit, Size>{
      BoxFit.fill: Size(300, 300),
      BoxFit.contain: Size(300, 150),
      BoxFit.cover: Size(600, 300),
      BoxFit.fitWidth: Size(300, 150),
      BoxFit.fitHeight: Size(600, 300),
      BoxFit.none: Size(200, 100),
      BoxFit.scaleDown: Size(200, 100),
    };

    for (final entry in expected.entries) {
      BoxConstraints? surfaceConstraints;
      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            key: ValueKey(entry.key),
            source: _source('fit-${entry.key.name}'),
            controller: controller,
            autoplay: false,
            fit: entry.key,
            videoSurfaceBuilder: (context, value) => LayoutBuilder(
              builder: (context, constraints) {
                surfaceConstraints = constraints;
                return const SizedBox.expand();
              },
            ),
          ),
          width: 300,
          height: 300,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        surfaceConstraints?.biggest,
        entry.value,
        reason: '${entry.key} surface size',
      );
      expect(tester.takeException(), isNull, reason: '${entry.key} overflow');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets(
    'default portrait fullscreen chrome stays usable with navigation and PiP',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402.6, 875.2);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = _FakeVideoPlayerController();

      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('complete-portrait-chrome'),
            controller: controller,
            width: 1920,
            height: 1080,
            autoplay: false,
            isFullscreen: true,
            onClose: () {},
            onPrevious: () {},
            onNext: () {},
            onFullscreenChanged: (_) {},
            onPictureInPictureChanged: (_) {},
          ),
          width: 402.6,
          height: 875.2,
          padding: const EdgeInsets.fromLTRB(0, 62, 0, 34),
          textScaler: const TextScaler.linear(1.3),
        ),
      );
      await tester.pumpAndSettle();

      final player = tester.getRect(find.byType(MithkaVideoPlayer));
      for (final label in <String>[
        'Close',
        'Previous video',
        'Play',
        'Next video',
        'Picture in picture',
        'Exit fullscreen',
      ]) {
        final control = _semanticsWidget(label);
        expect(
          control,
          label == 'Play' ? findsWidgets : findsOneWidget,
          reason: '$label is available',
        );
        final rect = tester.getRect(control.first);
        expect(player.contains(rect.topLeft), isTrue, reason: '$label top');
        expect(
          player.contains(rect.bottomRight),
          isTrue,
          reason: '$label bottom',
        );
      }
      expect(
        tester.getRect(_semanticsWidget('Close')).top - player.top,
        closeTo(76, 0.01),
      );
      expect(
        player.bottom -
            tester.getRect(_semanticsWidget('Picture in picture')).bottom,
        greaterThanOrEqualTo(34),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    },
  );

  testWidgets('custom chrome receives nullable navigation and safe actions', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    MithkaVideoChromeScope? scope;

    Widget player({VoidCallback? previous, VoidCallback? next}) => _frame(
      MithkaVideoPlayer(
        key: const ValueKey('custom-chrome'),
        source: _source('custom-chrome'),
        controller: controller,
        autoplay: false,
        interactionMode: MithkaVideoInteractionMode.delegateToChrome,
        onPrevious: previous,
        onNext: next,
        chromeBuilder: (context, value) {
          scope = value;
          return GestureDetector(
            key: const ValueKey('custom-play'),
            behavior: HitTestBehavior.opaque,
            onTap: value.actions.togglePlayback,
          );
        },
      ),
    );

    await tester.pumpWidget(player());
    await tester.pumpAndSettle();
    expect(scope, isNotNull);
    expect(scope!.previous, isNull);
    expect(scope!.next, isNull);
    expect(scope!.snapshot.playbackState, MithkaVideoPlaybackState.ready);
    expect(scope!.snapshot.displayPosition, Duration.zero);
    expect(scope!.snapshot.isPictureInPicture, isFalse);
    expect(scope!.snapshot.pictureInPictureRequestPending, isFalse);

    var previousCalls = 0;
    var nextCalls = 0;
    await tester.pumpWidget(
      player(previous: () => previousCalls++, next: () => nextCalls++),
    );
    await tester.pump();
    expect(scope!.previous, isNotNull);
    expect(scope!.next, isNotNull);
    scope!.previous!();
    scope!.next!();
    expect(previousCalls, 1);
    expect(nextCalls, 1);

    await tester.tap(find.byKey(const ValueKey('custom-play')));
    await tester.pump();
    expect(controller.value.isPlaying, isTrue);
    expect(scope!.snapshot.playbackState, MithkaVideoPlaybackState.playing);

    await scope!.actions.seekTo(const Duration(seconds: 42));
    await scope!.actions.setVolume(0.35);
    await scope!.actions.setPlaybackSpeed(1.5);
    await tester.pump();
    expect(controller.value.position, const Duration(seconds: 42));
    expect(controller.value.volume, 0.35);
    expect(controller.value.playbackSpeed, 1.5);

    final retainedActions = scope!.actions;
    final playCalls = controller.playCalls;
    final pauseCalls = controller.pauseCalls;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.disposed, isFalse);
    await retainedActions.togglePlayback();
    expect(controller.playCalls, playCalls);
    expect(controller.pauseCalls, pauseCalls);
    await controller.dispose();
  });

  testWidgets('explicit custom chrome toggle hides focused playing controls', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final controlFocus = FocusNode(debugLabel: 'custom chrome control');
    MithkaVideoChromeScope? scope;
    addTearDown(controlFocus.dispose);

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('focused-custom-chrome'),
          controller: controller,
          autoplay: false,
          controlsAutoHideDuration: const Duration(milliseconds: 80),
          interactionMode: MithkaVideoInteractionMode.delegateToChrome,
          chromeBuilder: (context, value) {
            scope = value;
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('custom-chrome-surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: value.actions.toggleControls,
                ),
                if (value.snapshot.controlsVisible)
                  Center(
                    child: Focus(
                      focusNode: controlFocus,
                      child: const SizedBox.square(dimension: 44),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controlFocus.requestFocus();
    await tester.pump();
    expect(controlFocus.hasFocus, isTrue);
    await controller.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scope!.snapshot.controlsVisible, isTrue);

    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('custom-chrome-surface')),
        )
        .onTap!();
    await tester.pump();
    expect(scope!.snapshot.controlsVisible, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('desktop surface clicks hide controls until the pointer moves', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('desktop-surface-controls'),
          controller: controller,
          autoplay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_controlOpacity(tester), 1);

    final player = find.byType(MithkaVideoPlayer);
    final surfacePoint = tester.getTopLeft(player) + const Offset(40, 120);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: surfacePoint);
    await tester.pump();
    await mouse.down(surfacePoint);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_controlOpacity(tester), 0);

    await mouse.down(surfacePoint);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_controlOpacity(tester), 0);

    await mouse.moveTo(surfacePoint + const Offset(20, 0));
    await tester.pump();
    expect(_controlOpacity(tester), 1);

    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets(
    'controlled picture in picture coalesces requests and updates default chrome',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      final requests = <bool>[];
      final errors = <MithkaVideoPlayerError>[];
      final firstRequest = Completer<void>();

      Widget player({required bool pictureInPicture}) => _frame(
        MithkaVideoPlayer(
          key: const ValueKey('picture-in-picture-player'),
          source: _source('picture-in-picture'),
          controller: controller,
          autoplay: false,
          autofocus: true,
          isPictureInPicture: pictureInPicture,
          onPictureInPictureChanged: (next) async {
            requests.add(next);
            if (requests.length == 1) await firstRequest.future;
            if (requests.length == 2) {
              throw StateError('picture in picture rejected');
            }
          },
          onError: errors.add,
        ),
      );

      await tester.pumpWidget(player(pictureInPicture: false));
      await tester.pumpAndSettle();
      expect(_semanticsWidget('Picture in picture'), findsOneWidget);
      expect(_semanticsWidget('Exit picture in picture'), findsNothing);

      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('Picture in picture'));
      await tester.pump();
      final pendingControl = tester.widget<Semantics>(
        _semanticsWidget('Picture in picture'),
      );
      expect(pendingControl.properties.enabled, isFalse);
      expect(
        find.descendant(
          of: _semanticsWidget('Picture in picture'),
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(requests, [isTrue]);

      firstRequest.complete();
      await tester.pump();
      await tester.pumpWidget(player(pictureInPicture: true));
      await tester.pump();
      expect(_semanticsWidget('Picture in picture'), findsNothing);
      expect(_semanticsWidget('Exit picture in picture'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(requests, [isTrue, isFalse]);
      expect(errors, hasLength(1));
      expect(errors.single.cause, isA<StateError>());
      expect(
        tester
            .widget<Semantics>(_semanticsWidget('Exit picture in picture'))
            .properties
            .enabled,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(requests, [isTrue, isFalse, isFalse]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
      await controller.dispose();
    },
  );

  testWidgets(
    'custom chrome sees pending PiP state and disposal ignores late completion',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      final request = Completer<void>();
      MithkaVideoChromeScope? scope;
      var requests = 0;

      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('custom-pip-pending'),
            controller: controller,
            autoplay: false,
            interactionMode: MithkaVideoInteractionMode.delegateToChrome,
            onPictureInPictureChanged: (next) async {
              requests++;
              await request.future;
            },
            chromeBuilder: (context, value) {
              scope = value;
              return GestureDetector(
                key: const ValueKey('custom-pip-action'),
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    unawaited(value.actions.requestPictureInPicture(true)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scope!.snapshot.pictureInPictureRequestPending, isFalse);

      await tester.tap(find.byKey(const ValueKey('custom-pip-action')));
      await tester.pump();
      expect(requests, 1);
      expect(scope!.snapshot.pictureInPictureRequestPending, isTrue);
      await scope!.actions.requestPictureInPicture(true);
      expect(requests, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      request.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await controller.dispose();
    },
  );

  testWidgets(
    'delegated interaction leaves surface gestures to custom chrome',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      final fullscreenRequests = <bool>[];

      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('delegated-interaction'),
            controller: controller,
            autoplay: false,
            interactionMode: MithkaVideoInteractionMode.delegateToChrome,
            onFullscreenChanged: fullscreenRequests.add,
            chromeBuilder: (context, scope) =>
                const SizedBox.expand(key: ValueKey('passive-custom-chrome')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(MithkaVideoPlayer));
      await tester.tapAt(center, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(center, kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.playCalls, 0);
      expect(controller.value.position, Duration.zero);

      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(fullscreenRequests, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.disposed, isFalse);
      await controller.dispose();
    },
  );

  testWidgets('builder controllers are replaced and disposed by the player', (
    tester,
  ) async {
    final controllers = <_FakeVideoPlayerController>[];
    VideoPlayerController buildController(MithkaVideoSource source) {
      final controller = _FakeVideoPlayerController();
      controllers.add(controller);
      return controller;
    }

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          key: const ValueKey('player'),
          source: _source('first'),
          controllerBuilder: buildController,
          autoplay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controllers, hasLength(1));

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          key: const ValueKey('player'),
          source: _source('second'),
          controllerBuilder: buildController,
          autoplay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(controllers.first.disposed, isTrue);
    expect(controllers.last.disposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controllers.last.disposed, isTrue);
  });

  testWidgets('initialization errors can retry with a fresh controller', (
    tester,
  ) async {
    final errors = <MithkaVideoPlayerError>[];
    final controllers = <_FakeVideoPlayerController>[];
    VideoPlayerController buildController(MithkaVideoSource source) {
      final controller = _FakeVideoPlayerController(
        initializeError: controllers.isEmpty
            ? StateError('test initialization failure')
            : null,
      );
      controllers.add(controller);
      return controller;
    }

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('retry'),
          controllerBuilder: buildController,
          autoplay: false,
          onError: errors.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(errors, hasLength(1));
    expect(find.text('This video could not be played'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(controllers.first.disposed, isTrue);
    expect(find.text('This video could not be played'), findsNothing);
    expect(_semanticsWidget('Play'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('keyboard and lifecycle policy preserve user intent', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final fullscreenRequests = <bool>[];
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await controller.dispose();
    });

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('keyboard'),
          controller: controller,
          autoplay: false,
          autofocus: true,
          isFullscreen: true,
          onFullscreenChanged: fullscreenRequests.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_semanticsWidget('Exit fullscreen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.value.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(controller.value.position, const Duration(seconds: 10));
    expect(controller.value.volume, 0);
    expect(fullscreenRequests, [false]);

    final playerCenter = tester.getCenter(find.byType(MithkaVideoPlayer));
    await tester.tapAt(playerCenter, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(playerCenter, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fullscreenRequests, [false, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.value.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    final playCalls = controller.playCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.playCalls, playCalls);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('compact layout and scrub preview stay inside the timeline', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final previewKey = GlobalKey();
    final previewPositions = <Duration>[];

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('scrub'),
          controller: controller,
          autoplay: true,
          thumbnailProvider: (_) async => null,
          scrubPreviewBuilder: (context, bytes, position) {
            previewPositions.add(position);
            return SizedBox(key: previewKey);
          },
        ),
        width: 500,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MithkaVideoSlider), findsOneWidget);

    final timeline = find.byType(MithkaVideoSlider);
    final timelineRect = tester.getRect(timeline);
    final gesture = await tester.startGesture(timelineRect.center);
    await gesture.moveTo(
      Offset(timelineRect.right - 1, timelineRect.center.dy),
    );
    await tester.pump();

    expect(previewPositions, isNotEmpty);
    final previewRect = tester.getRect(find.byKey(previewKey));
    expect(previewRect.left, greaterThanOrEqualTo(timelineRect.left - 0.01));
    expect(previewRect.right, lessThanOrEqualTo(timelineRect.right + 0.01));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      controller.value.position,
      greaterThan(const Duration(seconds: 110)),
    );
    expect(controller.value.isPlaying, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('lifecycle policy changes recreate a player-owned controller', (
    tester,
  ) async {
    final controllers = <_FakeVideoPlayerController>[];
    VideoPlayerController buildController(MithkaVideoSource source) {
      final controller = _FakeVideoPlayerController();
      controllers.add(controller);
      return controller;
    }

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          key: const ValueKey('lifecycle-player'),
          source: _source('lifecycle-replacement'),
          controllerBuilder: buildController,
          autoplay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          key: const ValueKey('lifecycle-player'),
          source: _source('lifecycle-replacement'),
          controllerBuilder: buildController,
          autoplay: false,
          lifecycleBehavior: MithkaVideoLifecycleBehavior.delegateToController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(controllers.first.disposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controllers.last.disposed, isTrue);
  });

  testWidgets('completion fires only after playback actually stops', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final states = <MithkaVideoPlaybackState>[];
    var ended = 0;
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('completion'),
          controller: controller,
          autoplay: false,
          onEnded: () => ended++,
          onPlaybackStateChanged: states.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.emit(
      position: controller.value.duration - const Duration(milliseconds: 100),
      isPlaying: true,
      isCompleted: false,
    );
    await tester.pump();
    expect(ended, 0);
    expect(states.last, MithkaVideoPlaybackState.playing);

    controller.emit(
      position: controller.value.duration,
      isPlaying: true,
      isCompleted: true,
    );
    await tester.pump();
    expect(ended, 0);
    expect(states.last, MithkaVideoPlaybackState.playing);

    controller.emit(isPlaying: false, isCompleted: true);
    await tester.pump();
    expect(ended, 1);
    expect(states.last, MithkaVideoPlaybackState.completed);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('looping media never reports a completed playback state', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final states = <MithkaVideoPlaybackState>[];
    var ended = 0;
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('loop-completion'),
          controller: controller,
          autoplay: false,
          looping: true,
          onEnded: () => ended++,
          onPlaybackStateChanged: states.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.emit(
      position: controller.value.duration,
      isPlaying: false,
      isCompleted: true,
    );
    await tester.pump();

    expect(ended, 0);
    expect(states.last, isNot(MithkaVideoPlaybackState.completed));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('controller replacement clears an in-flight scrub session', (
    tester,
  ) async {
    final controllers = <_FakeVideoPlayerController>[];
    final previewKey = GlobalKey();
    VideoPlayerController buildController(MithkaVideoSource source) {
      final controller = _FakeVideoPlayerController();
      controllers.add(controller);
      return controller;
    }

    Widget player(String source) => _frame(
      MithkaVideoPlayer(
        key: const ValueKey('replace-during-scrub'),
        source: _source(source),
        controllerBuilder: buildController,
        thumbnailProvider: (_) async => null,
        scrubPreviewBuilder: (context, bytes, position) =>
            SizedBox(key: previewKey),
      ),
      width: 500,
      height: 300,
    );

    await tester.pumpWidget(player('first-scrub'));
    await tester.pumpAndSettle();
    final timeline = find.byType(MithkaVideoSlider);
    final gesture = await tester.startGesture(tester.getCenter(timeline));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(find.byKey(previewKey), findsOneWidget);

    await tester.pumpWidget(player('second-scrub'));
    await tester.pumpAndSettle();
    expect(controllers, hasLength(2));
    expect(controllers.first.disposed, isTrue);
    expect(find.byKey(previewKey), findsNothing);
    expect(controllers.last.value.isPlaying, isTrue);

    await gesture.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controllers.last.disposed, isTrue);
  });

  testWidgets('key repeat preserves one scrub pause and resume intent', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('key-repeat'),
          controller: controller,
          thumbnailProvider: (_) async => null,
        ),
        width: 500,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    final pauseCalls = controller.pauseCalls;
    final playCalls = controller.playCalls;
    controller.pauseGate = Completer<void>();

    final timeline = find.semantics.byLabel('Playback position');
    tester.semantics.increase(timeline);
    tester.semantics.increase(timeline);
    tester.semantics.increase(timeline);
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    expect(controller.pauseCalls, pauseCalls + 1);

    controller.pauseGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);
    expect(controller.playCalls, playCalls + 1);
    expect(controller.value.position, const Duration(seconds: 30));
    semantics.dispose();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('scrub resume waits until the app is foregrounded', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await controller.dispose();
    });
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('scrub-lifecycle'),
          controller: controller,
          thumbnailProvider: (_) async => null,
        ),
        width: 500,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(MithkaVideoSlider);
    final gesture = await tester.startGesture(tester.getCenter(timeline));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'focused controls remain visible and hidden controls exclude focus',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            source: _source('control-focus'),
            controller: controller,
            controlsAutoHideDuration: const Duration(milliseconds: 500),
            thumbnailProvider: (_) async => null,
          ),
          width: 500,
          height: 300,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(tester.getCenter(find.byType(MithkaVideoSlider)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(_controlOpacity(tester), 1);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_controlOpacity(tester), 0);
      expect(
        tester.widget<ExcludeFocus>(find.byType(ExcludeFocus)).excluding,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    },
  );

  testWidgets('accessible navigation cancels an already scheduled hide', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final player = MithkaVideoPlayer(
      key: const ValueKey('accessible-controls'),
      source: _source('accessible-controls'),
      controller: controller,
      controlsAutoHideDuration: const Duration(milliseconds: 500),
    );
    await tester.pumpWidget(_frame(player, width: 500, height: 300));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(
      _frame(player, width: 500, height: 300, accessibleNavigation: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(_controlOpacity(tester), 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('compact controls do not overflow at embedded media widths', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    for (final width in <double>[160, 180, 220]) {
      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            key: const ValueKey('narrow-player'),
            source: _source('narrow'),
            controller: controller,
            autoplay: false,
            onPrevious: () {},
            onNext: () {},
            onFullscreenChanged: (_) {},
          ),
          width: width,
          height: 180,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width overflowed');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('short 16:9 chrome merges center and bottom transport controls', (
    tester,
  ) async {
    for (final size in <Size>[const Size(160, 90), const Size(220, 124)]) {
      final controller = _FakeVideoPlayerController();
      await tester.pumpWidget(
        _frame(
          MithkaVideoPlayer(
            key: ValueKey('short-${size.width}'),
            source: _source('short-${size.width}'),
            controller: controller,
            autoplay: false,
            onPrevious: () {},
            onNext: () {},
          ),
          width: size.width,
          height: size.height,
        ),
      );
      await tester.pumpAndSettle();

      expect(_semanticsWidget('Play'), findsOneWidget);
      expect(_semanticsWidget('Previous video'), findsOneWidget);
      expect(_semanticsWidget('Next video'), findsOneWidget);
      expect(find.byType(MithkaVideoSlider), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'overlap at $size');

      final timeline = tester.getRect(find.byType(MithkaVideoSlider));
      final previous = tester.getRect(_semanticsWidget('Previous video'));
      final play = tester.getRect(_semanticsWidget('Play'));
      final next = tester.getRect(_semanticsWidget('Next video'));
      final player = tester.getRect(find.byType(MithkaVideoPlayer));
      expect(timeline.bottom, lessThanOrEqualTo(play.top));
      expect(previous.right, lessThanOrEqualTo(play.left));
      expect(play.right, lessThanOrEqualTo(next.left));
      expect(player.contains(previous.topLeft), isTrue);
      expect(player.contains(next.bottomRight), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.disposed, isFalse);
      await controller.dispose();
    }
  });

  testWidgets('scrub preview uses the controller aspect ratio', (tester) async {
    final controller = _FakeVideoPlayerController(
      videoSize: const Size(720, 1280),
    );
    final previewKey = GlobalKey();
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('portrait-preview'),
          controller: controller,
          autoplay: false,
          thumbnailProvider: (_) async => null,
          scrubPreviewBuilder: (context, bytes, position) =>
              SizedBox(key: previewKey),
        ),
        width: 500,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MithkaVideoSlider)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(previewKey)).height, 110);
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('thumbnail work is debounced and a hung provider times out', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    final requests = <Completer<Uint8List?>>[];
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('thumbnail-timeout'),
          controller: controller,
          autoplay: false,
          thumbnailProvider: (_) {
            final request = Completer<Uint8List?>();
            requests.add(request);
            return request.future;
          },
        ),
        width: 500,
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(MithkaVideoSlider);
    var gesture = await tester.startGesture(tester.getCenter(timeline));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 199));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, hasLength(1));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    gesture = await tester.startGesture(tester.getCenter(timeline));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(requests, hasLength(2));
    await gesture.cancel();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets(
    'scroll volume claims the pointer signal from an outer scroll view',
    (tester) async {
      final controller = _FakeVideoPlayerController();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(500, 220)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 500,
              height: 220,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    SizedBox(
                      height: 300,
                      child: MithkaVideoPlayer(
                        source: _source('scroll-volume'),
                        controller: controller,
                        autoplay: false,
                        initialVolume: 0.5,
                        enableScrollVolume: true,
                      ),
                    ),
                    const SizedBox(height: 500),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(MithkaVideoPlayer)),
          scrollDelta: const Offset(0, 20),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(scrollController.offset, 0);
      expect(controller.value.volume, closeTo(0.45, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    },
  );

  testWidgets('caption semantics replace the duplicate text semantics', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    await tester.pumpWidget(
      _frame(
        MithkaVideoPlayer(
          source: _source('captions'),
          controller: controller,
          autoplay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.emit(
      caption: const Caption(
        number: 1,
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: 'One announcement',
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'One announcement' &&
            widget.excludeSemantics,
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });

  testWidgets('time and speed labels ignore inherited link decoration', (
    tester,
  ) async {
    final controller = _FakeVideoPlayerController();
    await tester.pumpWidget(
      _frame(
        DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFFFFF00),
            fontSize: 24,
            decoration: TextDecoration.underline,
          ),
          child: MithkaVideoPlayer(
            source: _source('desktop-label-style'),
            controller: controller,
            autoplay: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final time = tester.widget<Text>(find.text('0:00 / 2:00'));
    final speed = tester.widget<Text>(find.text('1x'));
    for (final label in [time, speed]) {
      expect(label.style?.inherit, isFalse);
      expect(label.style?.color, const Color(0xFFFFFFFF));
      expect(label.style?.fontWeight, FontWeight.normal);
      expect(label.style?.decoration, TextDecoration.none);
    }
    expect(time.style?.fontSize, 13);
    expect(speed.style?.fontSize, 13);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.dispose();
  });
}

double _controlOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedOpacity &&
            widget.duration == const Duration(milliseconds: 170),
      ),
    )
    .opacity;

MithkaVideoSource _source(String id) =>
    MithkaVideoSource.network('https://media.example/$id.mp4');

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Widget _frame(
  Widget child, {
  double width = 1024,
  double height = 768,
  EdgeInsets padding = EdgeInsets.zero,
  bool accessibleNavigation = false,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) => MediaQuery(
  data: MediaQueryData(
    size: Size(width, height),
    padding: padding,
    accessibleNavigation: accessibleNavigation,
    textScaler: textScaler,
  ),
  child: Directionality(
    textDirection: textDirection,
    child: Center(
      child: SizedBox(width: width, height: height, child: child),
    ),
  ),
);

class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController({
    this.initializeError,
    this.videoSize = const Size(1280, 720),
    this.setLoopingError,
    bool initialized = false,
  }) : super.networkUrl(Uri.parse('https://media.example/fake.mp4')) {
    if (initialized) {
      value = value.copyWith(
        duration: const Duration(minutes: 2),
        size: videoSize,
        isInitialized: true,
      );
    }
  }

  final Object? initializeError;
  final Size videoSize;
  final Object? setLoopingError;
  Completer<void>? pauseGate;
  Completer<void>? setLoopingGate;
  int initializeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int setLoopingCalls = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final error = initializeError;
    if (error != null) throw error;
    value = value.copyWith(
      duration: const Duration(minutes: 2),
      size: videoSize,
      isInitialized: true,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    value = value.copyWith(isPlaying: false);
    await pauseGate?.future;
  }

  @override
  Future<void> setLooping(bool looping) async {
    setLoopingCalls++;
    await setLoopingGate?.future;
    final error = setLoopingError;
    if (error != null) throw error;
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> seekTo(Duration position) async {
    final clamped = position < Duration.zero
        ? Duration.zero
        : position > value.duration
        ? value.duration
        : position;
    value = value.copyWith(
      position: clamped,
      isCompleted: clamped == value.duration,
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  void emit({
    Duration? position,
    bool? isPlaying,
    bool? isCompleted,
    Caption? caption,
  }) {
    value = value.copyWith(
      position: position,
      isPlaying: isPlaying,
      isCompleted: isCompleted,
      caption: caption,
    );
  }
}
