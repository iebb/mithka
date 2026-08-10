import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/moments/story_viewer_view.dart';
import 'package:mithka/profile/profile_detail_view.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('featured profile photos use a native window only on desktop', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      expect(profileFeaturedPhotosUseDesktopWindow(platform), isTrue);
    }
    expect(profileFeaturedPhotosUseDesktopWindow(TargetPlatform.iOS), isFalse);
    expect(
      profileFeaturedPhotosUseDesktopWindow(TargetPlatform.macOS, isWeb: true),
      isFalse,
    );
    expect(
      profileFeaturedPhotosUseDesktopWindow(
        TargetPlatform.macOS,
        hasProfileActions: true,
      ),
      isFalse,
    );

    final source = File(
      'lib/profile/profile_detail_view.dart',
    ).readAsStringSync();
    expect(source, contains('DesktopImagePreviewWindowService.instance.open('));
    expect(source, contains('if (opened) return;'));
    expect(source, contains('FullImageViewer('));
  });

  test('desktop story shortcuts preserve reply-field editing', () {
    expect(
      storyViewerDesktopCommandForKey(
        LogicalKeyboardKey.escape,
        replyHasFocus: true,
      ),
      StoryViewerDesktopCommand.close,
    );
    expect(
      storyViewerDesktopCommandForKey(
        LogicalKeyboardKey.arrowLeft,
        replyHasFocus: false,
      ),
      StoryViewerDesktopCommand.previous,
    );
    expect(
      storyViewerDesktopCommandForKey(
        LogicalKeyboardKey.arrowRight,
        replyHasFocus: false,
      ),
      StoryViewerDesktopCommand.next,
    );
    expect(
      storyViewerDesktopCommandForKey(
        LogicalKeyboardKey.space,
        replyHasFocus: false,
      ),
      StoryViewerDesktopCommand.togglePlayback,
    );
    expect(
      storyViewerDesktopCommandForKey(
        LogicalKeyboardKey.space,
        replyHasFocus: true,
      ),
      isNull,
    );
  });

  testWidgets('desktop story navigation appears on pointer hover', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: StoryViewerView(chatId: 1, storyIds: [])),
    );
    await tester.pump();

    final previous = find.byKey(const ValueKey('storyDesktopPrevious'));
    final next = find.byKey(const ValueKey('storyDesktopNext'));
    expect(previous, findsOneWidget);
    expect(next, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(previous).opacity, 0);
    expect(tester.widget<AnimatedOpacity>(next).opacity, 0);
    final gestureSurface = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('storyGestureSurface')),
    );
    expect(gestureSurface.onLongPressStart, isNull);
    expect(gestureSurface.onHorizontalDragEnd, isNull);
    expect(gestureSurface.onVerticalDragEnd, isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(450, 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(tester.widget<AnimatedOpacity>(previous).opacity, 1);
    expect(tester.widget<AnimatedOpacity>(next).opacity, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Escape closes a desktop story route', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.expand()),
    );

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const StoryViewerView(chatId: 1, storyIds: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(StoryViewerView), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'StoryViewerDesktopKeyboard',
    );

    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(handled, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(StoryViewerView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('story shortcuts do not act below a desktop dialog', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.expand()),
    );
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const StoryViewerView(chatId: 1, storyIds: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    unawaited(
      showDialog<void>(
        context: navigatorKey.currentState!.overlay!.context,
        builder: (_) => const Dialog(child: Text('blocking-dialog')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(find.text('blocking-dialog'), findsOneWidget);
    expect(find.byType(StoryViewerView), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 250));
    navigatorKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 700));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mouse drag does not navigate or close a desktop story', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.expand()),
    );
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const StoryViewerView(chatId: 1, storyIds: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final mouseDrag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('storyGestureSurface'))),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouseDrag.removePointer);
    await mouseDrag.moveBy(const Offset(0, 360));
    await mouseDrag.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(StoryViewerView), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 700));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('touch story viewer retains swipe-down dismissal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.expand()),
    );
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const StoryViewerView(chatId: 1, storyIds: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('storyDesktopHoverRegion')), findsNothing);
    expect(find.byKey(const ValueKey('storyDesktopPrevious')), findsNothing);
    expect(find.byKey(const ValueKey('storyDesktopNext')), findsNothing);
    final gestureSurface = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('storyGestureSurface')),
    );
    expect(gestureSurface.onLongPressStart, isNotNull);
    expect(gestureSurface.onHorizontalDragEnd, isNotNull);
    expect(gestureSurface.onVerticalDragEnd, isNotNull);

    gestureSurface.onVerticalDragEnd!(
      DragEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(0, 1000)),
        primaryVelocity: 1000,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(StoryViewerView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
