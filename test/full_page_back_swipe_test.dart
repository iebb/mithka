import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/components/full_page_back_swipe.dart';

const _previousColor = Color(0xFF20C878);
const _chatColor = Color(0xFFF4E8D8);
const _legacyFallbackColor = Color(0xFF111318);
const _previousKey = ValueKey('previous-route');
const _chatKey = ValueKey('chat-route');
const _fallbackChildKey = ValueKey('fallback-child');

Color _expectedRevealedColor(double progress) => Color.alphaBlend(
  Color.fromRGBO(0, 0, 0, 0.16 * (1 - progress)),
  _previousColor,
);

void _expectColorClose(Color actual, Color expected) {
  final actualValue = actual.toARGB32();
  final expectedValue = expected.toARGB32();
  for (final shift in [16, 8, 0]) {
    expect(
      (actualValue >> shift) & 0xFF,
      closeTo((expectedValue >> shift) & 0xFF, 2),
    );
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _RouteHarness {
  final navigatorKey = GlobalKey<NavigatorState>();
  final boundaryKey = GlobalKey();
  final observer = _CountingNavigatorObserver();
  int prepareCount = 0;
}

Future<_RouteHarness> _pumpRouteHarness(
  WidgetTester tester, {
  bool canPop = true,
  VoidCallback? onBack,
  VoidCallback? beforeRoutePop,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _RouteHarness();
  await tester.pumpWidget(
    RepaintBoundary(
      key: harness.boundaryKey,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        navigatorKey: harness.navigatorKey,
        navigatorObservers: [harness.observer],
        home: const ColoredBox(key: _previousKey, color: _previousColor),
      ),
    ),
  );
  unawaited(
    harness.navigatorKey.currentState!.push<void>(
      AppChatPageRoute<void>(
        builder: (_) => PopScope<void>(
          canPop: canPop,
          onPopInvokedWithResult: (_, _) {},
          child: FullPageBackSwipe(
            enabled: true,
            onBack: onBack ?? () => harness.navigatorKey.currentState!.pop(),
            beforeRoutePop: beforeRoutePop ?? () => harness.prepareCount++,
            child: const ColoredBox(key: _chatKey, color: _chatColor),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<Color> _pixelAt(
  WidgetTester tester,
  _RouteHarness harness,
  Offset point,
) async {
  return (await tester.runAsync(() async {
    final boundary =
        harness.boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final x = point.dx.floor();
    final y = point.dy.floor();
    final offset = (y * image.width + x) * 4;
    final color = Color.fromARGB(
      bytes!.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}

void main() {
  testWidgets('back swipe can begin from the middle of the page', (
    tester,
  ) async {
    var backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullPageBackSwipe(
            enabled: true,
            onBack: () => backCount++,
            child: const SizedBox.expand(key: _fallbackChildKey),
          ),
        ),
      ),
    );

    final pageCenter = tester.getCenter(find.byType(FullPageBackSwipe));
    expect(pageCenter.dx, greaterThan(28));
    final gesture = await tester.startGesture(pageCenter);
    await gesture.moveBy(const Offset(130, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(_fallbackChildKey)).dx, 0);

    await gesture.up();
    await tester.pump();

    expect(backCount, 1);
  });

  testWidgets('short horizontal drags do not trigger back', (tester) async {
    var backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullPageBackSwipe(
            enabled: true,
            onBack: () => backCount++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(FullPageBackSwipe));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();

    expect(backCount, 0);
  });

  testWidgets('vertical and disabled swipes do not navigate back', (
    tester,
  ) async {
    var enabled = true;
    var backCount = 0;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            setState = update;
            return FullPageBackSwipe(
              enabled: enabled,
              onBack: () => backCount++,
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );

    final center = tester.getCenter(find.byType(FullPageBackSwipe));
    var gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 130));
    await gesture.up();
    await tester.pump();
    expect(backCount, 0);

    setState(() => enabled = false);
    await tester.pump();
    gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(130, 0));
    await gesture.up();
    await tester.pump();
    expect(backCount, 0);
  });

  testWidgets('a route veto does not fall through to the legacy back action', (
    tester,
  ) async {
    var backCount = 0;
    final harness = await _pumpRouteHarness(
      tester,
      canPop: false,
      onBack: () => backCount++,
    );
    final gesture = await tester.startGesture(const Offset(195, 422));

    await gesture.moveBy(const Offset(140, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(backCount, 0);
    expect(harness.observer.popCount, 0);
    expect(harness.navigatorKey.currentState!.canPop(), isTrue);
    expect(tester.getTopLeft(find.byKey(_chatKey)).dx, 0);
  });

  testWidgets('a failing exit hook restores and unlocks the route gesture', (
    tester,
  ) async {
    var shouldThrow = true;
    final harness = await _pumpRouteHarness(
      tester,
      beforeRoutePop: () {
        if (!shouldThrow) return;
        shouldThrow = false;
        throw StateError('exit preparation failed');
      },
    );
    var gesture = await tester.startGesture(const Offset(195, 422));

    await gesture.moveBy(const Offset(140, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<StateError>());
    expect(harness.observer.popCount, 0);
    expect(tester.getTopLeft(find.byKey(_chatKey)).dx, closeTo(0, 0.5));

    gesture = await tester.startGesture(const Offset(195, 422));
    await gesture.moveBy(const Offset(140, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.observer.popCount, 1);
    expect(find.byKey(_chatKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mid drag paints the previous route under the chat surface', (
    tester,
  ) async {
    final harness = await _pumpRouteHarness(tester);
    final gesture = await tester.startGesture(const Offset(195, 422));

    await gesture.moveBy(const Offset(156, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(_chatKey)).dx, closeTo(156, 0.5));
    expect(tester.getSize(find.byKey(_chatKey)).width, 390);
    final revealedColor = await _pixelAt(
      tester,
      harness,
      const Offset(24, 420),
    );
    expect(
      revealedColor.computeLuminance(),
      lessThan(_previousColor.computeLuminance()),
    );
    expect(
      revealedColor.computeLuminance(),
      greaterThan(_legacyFallbackColor.computeLuminance()),
    );
    _expectColorClose(revealedColor, _expectedRevealedColor(0.4));
    expect(
      (await _pixelAt(tester, harness, const Offset(300, 420))).toARGB32(),
      _chatColor.toARGB32(),
    );

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('the revealed route brightens as the swipe progresses', (
    tester,
  ) async {
    final harness = await _pumpRouteHarness(tester);
    final gesture = await tester.startGesture(const Offset(195, 422));

    await gesture.moveBy(const Offset(78, 0));
    await tester.pump();
    final earlyColor = await _pixelAt(tester, harness, const Offset(24, 420));

    await gesture.moveBy(const Offset(156, 0));
    await tester.pump();
    final laterColor = await _pixelAt(tester, harness, const Offset(24, 420));

    expect(
      laterColor.computeLuminance(),
      greaterThan(earlyColor.computeLuminance()),
    );
    expect(
      laterColor.computeLuminance(),
      lessThan(_previousColor.computeLuminance()),
    );
    _expectColorClose(earlyColor, _expectedRevealedColor(0.2));
    _expectColorClose(laterColor, _expectedRevealedColor(0.6));

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('cancelled drag restores the chat without popping', (
    tester,
  ) async {
    final harness = await _pumpRouteHarness(tester);
    final gesture = await tester.startGesture(const Offset(195, 422));

    await gesture.moveBy(const Offset(140, 0));
    await gesture.moveBy(const Offset(-105, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.observer.popCount, 0);
    expect(harness.prepareCount, 0);
    expect(harness.navigatorKey.currentState!.canPop(), isTrue);
    expect(tester.getTopLeft(find.byKey(_chatKey)).dx, closeTo(0, 0.5));
    for (final x in [1.0, 195.0, 388.0]) {
      expect(
        (await _pixelAt(tester, harness, Offset(x, 420))).toARGB32(),
        _chatColor.toARGB32(),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary pop keeps the compact non-interactive transition', (
    tester,
  ) async {
    final harness = await _pumpRouteHarness(tester);

    harness.navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final chatLeft = tester.getTopLeft(find.byKey(_chatKey)).dx;
    expect(chatLeft, greaterThan(0));
    expect(chatLeft, lessThan(30));

    await tester.pumpAndSettle();
    expect(harness.observer.popCount, 1);
    expect(find.byKey(_chatKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'committed drag uses one exit motion without an opaque dark curtain',
    (tester) async {
      final harness = await _pumpRouteHarness(tester);
      final gesture = await tester.startGesture(const Offset(195, 422));

      await gesture.moveBy(const Offset(140, 0));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 90));

      final chatLeft = tester.getTopLeft(find.byKey(_chatKey)).dx;
      expect(chatLeft, greaterThan(140));
      expect(chatLeft, lessThan(390));
      final revealedColor = await _pixelAt(
        tester,
        harness,
        const Offset(24, 420),
      );
      expect(
        revealedColor.computeLuminance(),
        lessThan(_previousColor.computeLuminance()),
      );
      expect(
        revealedColor.computeLuminance(),
        greaterThan(_legacyFallbackColor.computeLuminance()),
      );
      _expectColorClose(revealedColor, _expectedRevealedColor(chatLeft / 390));
      expect(
        (await _pixelAt(
          tester,
          harness,
          Offset((chatLeft + 12).clamp(0, 389), 420),
        )).toARGB32(),
        _chatColor.toARGB32(),
      );

      await tester.pumpAndSettle();

      expect(harness.observer.popCount, 1);
      expect(harness.prepareCount, 1);
      expect(find.byKey(_chatKey), findsNothing);
      for (final x in [24.0, 195.0, 366.0]) {
        expect(
          (await _pixelAt(tester, harness, Offset(x, 420))).toARGB32(),
          _previousColor.toARGB32(),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
