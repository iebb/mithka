import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/media/inline_video_motion_guard.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:video_player/video_player.dart';

const _previewKey = ValueKey('inline-still-preview');
const _surfaceKey = ValueKey('inline-native-surface');

void main() {
  for (final viewType in VideoViewType.values) {
    testWidgets(
      '$viewType keeps inline content aligned during scrolling',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 360,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: Column(
                      children: [
                        const SizedBox(height: 150),
                        _inline(viewType),
                        const SizedBox(height: 1000),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_surfaceKey), findsOneWidget);
        final initialSurface = tester.element(find.byKey(_surfaceKey));

        // Programmatic jumps such as pinned-message navigation animate too.
        unawaited(
          scroll.animateTo(
            60,
            duration: const Duration(milliseconds: 240),
            curve: Curves.linear,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final direct = viewType == VideoViewType.platformView;
        expect(find.byKey(_surfaceKey), direct ? findsNothing : findsOneWidget);
        expect(find.byKey(_previewKey), direct ? findsOneWidget : findsNothing);
        if (direct) expect(tester.getSize(find.byKey(_previewKey)).height, 100);
        await tester.pumpAndSettle();
        expect(find.byKey(_surfaceKey), findsOneWidget);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(SingleChildScrollView)),
        );
        await gesture.moveBy(const Offset(0, -50));
        await tester.pump();
        expect(find.byKey(_surfaceKey), direct ? findsNothing : findsOneWidget);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(find.byKey(_surfaceKey), findsOneWidget);
        expect(
          identical(initialSurface, tester.element(find.byKey(_surfaceKey))),
          !direct,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'route movement detaches native view and canceled back restores it',
    (tester) async {
      const viewType = VideoViewType.platformView;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
      );
      final route = _ControlledRoute(_inline(viewType));
      unawaited(navigator.currentState!.push(route));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(_surfaceKey), findsNothing);
      expect(find.byKey(_previewKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(_surfaceKey), findsOneWidget);

      route.progress = 0.6;
      await tester.pump();
      expect(find.byKey(_surfaceKey), findsNothing);
      route.progress = 1;
      await tester.pump();
      expect(find.byKey(_surfaceKey), findsOneWidget);

      final covering = _ControlledRoute(const SizedBox.shrink());
      unawaited(navigator.currentState!.push(covering));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(_surfaceKey, skipOffstage: false), findsNothing);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_surfaceKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'other platforms retain their video while scrolling',
    (tester) async {
      const viewType = VideoViewType.platformView;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [_inline(viewType), const SizedBox(height: 1200)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        scroll.animateTo(
          40,
          duration: const Duration(milliseconds: 240),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(_surfaceKey), findsOneWidget);
      expect(find.byKey(_previewKey), findsNothing);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final size in [const Size(390, 844), const Size(900, 600)]) {
    for (final viewType in VideoViewType.values) {
      testWidgets(
        '$viewType handles a comment-style modal at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
          );
          late BuildContext pageContext;
          final page = AppChatPageRoute<void>(
            builder: (context) {
              pageContext = context;
              return Scaffold(body: Center(child: _inline(viewType)));
            },
          );
          unawaited(navigator.currentState!.push(page));
          await tester.pumpAndSettle();
          expect(find.byKey(_surfaceKey), findsOneWidget);

          unawaited(
            showAppModalSheet<void>(
              context: pageContext,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 0.72,
                child: ColoredBox(
                  key: ValueKey('comment-sheet-body'),
                  color: Colors.white,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final detach =
              defaultTargetPlatform == TargetPlatform.android &&
              viewType == VideoViewType.platformView;
          expect(
            find.byKey(_surfaceKey),
            detach ? findsNothing : findsOneWidget,
          );
          await tester.pumpAndSettle();

          expect(page.isCurrent, isFalse);
          // A popup does not animate the underlying chat route. This is the
          // path the scrolling/page-transition tests cannot exercise.
          expect(page.secondaryAnimation!.isDismissed, isTrue);
          expect(
            find.byKey(_surfaceKey),
            detach ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(_previewKey),
            detach ? findsOneWidget : findsNothing,
          );

          if (size.width < size.height) {
            final body = find.byKey(const ValueKey('comment-sheet-body'));
            final initialTop = tester.getTopLeft(body).dy;
            final drag = await tester.startGesture(tester.getCenter(body));
            await drag.moveBy(
              const Offset(0, 25),
              timeStamp: const Duration(milliseconds: 100),
            );
            await drag.moveBy(
              const Offset(0, 25),
              timeStamp: const Duration(milliseconds: 200),
            );
            await tester.pump();
            expect(tester.getTopLeft(body).dy, greaterThan(initialTop));
            expect(
              find.byKey(_surfaceKey),
              detach ? findsNothing : findsOneWidget,
            );
            await drag.up(timeStamp: const Duration(milliseconds: 500));
            await tester.pumpAndSettle();
            expect(find.byType(BottomSheet), findsOneWidget);
            expect(
              find.byKey(_surfaceKey),
              detach ? findsNothing : findsOneWidget,
            );
          }

          // A second popup must not accidentally restore the underlying video
          // when only the topmost route is dismissed.
          unawaited(
            navigator.currentState!.push(
              RawDialogRoute<void>(
                pageBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(
            find.byKey(_surfaceKey),
            detach ? findsNothing : findsOneWidget,
          );

          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(page.isCurrent, isTrue);
          expect(find.byKey(_surfaceKey), findsOneWidget);
          expect(find.byKey(_previewKey), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
        }),
      );
    }
  }
}

Widget _inline(VideoViewType viewType) => SizedBox(
  height: 100,
  width: 300,
  child: InlineVideoMotionGuard(
    viewType: viewType,
    placeholder: const ColoredBox(key: _previewKey, color: Color(0xffeeeeee)),
    // A keyed view lets the test distinguish detachment from hidden painting.
    child: const SizedBox.expand(key: _surfaceKey),
  ),
);

class _ControlledRoute extends PageRouteBuilder<void> {
  _ControlledRoute(Widget child)
    : super(
        pageBuilder: (_, _, _) => Scaffold(body: Center(child: child)),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      );

  set progress(double value) => controller!.value = value;
}
