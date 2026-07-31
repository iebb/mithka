import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_scroll_metrics.dart';

void main() {
  test('loaded message jumps wait for the retargeted key layout', () {
    final source = File('lib/chat/chat_view.dart').readAsStringSync();
    final methodStart = source.indexOf(
      'Future<bool> _scrollToMessageAndReport(',
    );
    final methodEnd = source.indexOf(
      'Future<void> _openHashtagSearch(',
      methodStart,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    final layoutWait = method.indexOf(
      'await WidgetsBinding.instance.endOfFrame;',
    );
    final mountedGuard = method.indexOf('if (!mounted ||', layoutWait);
    final loadedFastPath = method.indexOf('if (_vm.messages.any');
    expect(layoutWait, greaterThanOrEqualTo(0));
    expect(mountedGuard, greaterThan(layoutWait));
    expect(mountedGuard, lessThan(loadedFastPath));
  });

  test('session unread history loads carry cancellation through mutation', () {
    final viewSource = File('lib/chat/chat_view.dart').readAsStringSync();
    final sessionJumpStart = viewSource.indexOf(
      'Future<bool> _jumpToFirstUnreadImpl(',
    );
    final sessionJumpEnd = viewSource.indexOf(
      'void _scheduleSendFailureDialog(',
      sessionJumpStart,
    );
    final sessionJump = viewSource.substring(sessionJumpStart, sessionJumpEnd);
    final boundaryLoad = sessionJump.indexOf('await _vm.loadAroundMessage(');
    final boundaryLoadEnd = sessionJump.indexOf(');', boundaryLoad);
    expect(boundaryLoad, greaterThanOrEqualTo(0));
    expect(
      sessionJump.substring(boundaryLoad, boundaryLoadEnd),
      contains('isCancelled: isCancelled'),
    );

    final scrollStart = viewSource.indexOf(
      'Future<bool> _scrollToMessageAndReport(',
    );
    final scrollEnd = viewSource.indexOf(
      'Future<void> _openHashtagSearch(',
      scrollStart,
    );
    final sessionScroll = viewSource.substring(scrollStart, scrollEnd);
    final targetLoad = sessionScroll.indexOf('await _vm.loadAroundMessage(');
    final targetLoadEnd = sessionScroll.indexOf(');', targetLoad);
    expect(targetLoad, greaterThanOrEqualTo(0));
    expect(
      sessionScroll.substring(targetLoad, targetLoadEnd),
      contains('isCancelled: isCancelled'),
    );

    final modelSource = File(
      'lib/chat/chat_view_model.dart',
    ).readAsStringSync();
    final modelMethodStart = modelSource.indexOf(
      'Future<bool> loadAroundMessage(',
    );
    final modelMethodEnd = modelSource.indexOf(
      'Future<int?> openNextUnreadMention(',
      modelMethodStart,
    );
    final modelMethod = modelSource.substring(modelMethodStart, modelMethodEnd);
    expect(modelMethod, contains('bool Function()? isCancelled'));

    final initialCancellation = modelMethod.indexOf(
      'if (_chatOpenWorkIsStale || cancelled()) return false;',
    );
    final generationMutation = modelMethod.indexOf(
      '++_historyWindowGeneration',
    );
    expect(initialCancellation, greaterThanOrEqualTo(0));
    expect(initialCancellation, lessThan(generationMutation));

    final firstAwait = modelMethod.indexOf(
      'final targetRaw = await _client.query(',
    );
    final firstPostAwaitCancellation = modelMethod.indexOf(
      'if (cancelled()) return false;',
      firstAwait,
    );
    final targetParse = modelMethod.indexOf(
      'final target = TDParse.message(targetRaw);',
      firstAwait,
    );
    expect(firstPostAwaitCancellation, greaterThan(firstAwait));
    expect(firstPostAwaitCancellation, lessThan(targetParse));

    final secondAwait = modelMethod.indexOf(
      'final response = await _client.query(',
      targetParse,
    );
    final secondPostAwaitCancellation = modelMethod.indexOf(
      'if (cancelled()) return false;',
      secondAwait,
    );
    final batchMutation = modelMethod.indexOf('batch.addAll(', secondAwait);
    expect(secondPostAwaitCancellation, greaterThan(secondAwait));
    expect(secondPostAwaitCancellation, lessThan(batchMutation));

    final sharedMutation = modelMethod.indexOf(
      'if (replaceCurrentWindow)',
      batchMutation,
    );
    final finalCancellation = modelMethod.lastIndexOf(
      'cancelled()',
      sharedMutation,
    );
    expect(finalCancellation, greaterThan(batchMutation));
    expect(finalCancellation, lessThan(sharedMutation));
  });

  test('external target navigation invalidates session reopen navigation', () {
    final source = File('lib/chat/chat_view.dart').readAsStringSync();

    final unreadWrapperStart = source.indexOf(
      'Future<void> _jumpToFirstUnread()',
    );
    final unreadWrapperEnd = source.indexOf(
      'Future<bool> _jumpToFirstUnreadForSession(',
      unreadWrapperStart,
    );
    final unreadWrapper = source.substring(
      unreadWrapperStart,
      unreadWrapperEnd,
    );
    final unreadCancellation = unreadWrapper.indexOf(
      '_cancelSessionReopenNavigation(userClaimedViewport: true);',
    );
    final unreadDelegate = unreadWrapper.indexOf(
      'await _jumpToFirstUnreadImpl();',
    );
    expect(unreadCancellation, greaterThanOrEqualTo(0));
    expect(unreadCancellation, lessThan(unreadDelegate));

    final sessionUnreadWrapperEnd = source.indexOf(
      'Future<bool> _jumpToFirstUnreadImpl(',
      unreadWrapperEnd,
    );
    final sessionUnreadWrapper = source.substring(
      unreadWrapperEnd,
      sessionUnreadWrapperEnd,
    );
    expect(
      sessionUnreadWrapper,
      isNot(contains('_cancelSessionReopenNavigation')),
    );

    final targetWrapperStart = source.indexOf('Future<void> _scrollToMessage(');
    final targetWrapperEnd = source.indexOf(
      'Future<bool> _scrollToMessageAndReport(',
      targetWrapperStart,
    );
    final targetWrapper = source.substring(
      targetWrapperStart,
      targetWrapperEnd,
    );
    final targetCancellation = targetWrapper.indexOf(
      '_cancelSessionReopenNavigation(userClaimedViewport: true);',
    );
    final targetDelegate = targetWrapper.indexOf(
      'await _scrollToMessageAndReport(',
    );
    expect(targetCancellation, greaterThanOrEqualTo(0));
    expect(targetCancellation, lessThan(targetDelegate));

    final reportEnd = source.indexOf(
      'Future<void> _openHashtagSearch(',
      targetWrapperEnd,
    );
    final sessionReport = source.substring(targetWrapperEnd, reportEnd);
    expect(sessionReport, isNot(contains('_cancelSessionReopenNavigation')));

    expect(source, contains('unawaited(_jumpToFirstUnread())'));
    expect(source, contains('_scrollToMessage(pinned.id, pinnedJump: true)'));
    expect(source, contains('await _scrollToMessage(messageId)'));
    expect(source, contains('await _scrollToMessage(result)'));
  });

  group('oldest history pull', () {
    test(
      'fires once after accumulated clamped overscroll crosses threshold',
      () {
        final pull = OldestHistoryPullController(triggerDistance: 50);

        expect(pull.addClampedOverscroll(-18), isFalse);
        expect(pull.addClampedOverscroll(-31), isFalse);
        expect(pull.addClampedOverscroll(-2), isTrue);
        expect(pull.distance, 51);
        expect(pull.triggered, isTrue);
        expect(pull.addClampedOverscroll(-100), isFalse);
      },
    );

    test('reset arms the next pull and ignores movement toward latest', () {
      final pull = OldestHistoryPullController(triggerDistance: 30);

      expect(pull.addClampedOverscroll(40), isFalse);
      expect(pull.distance, 0);
      expect(pull.addClampedOverscroll(-30), isTrue);

      pull.reset();

      expect(pull.triggered, isFalse);
      expect(pull.distance, 0);
      expect(pull.addClampedOverscroll(-30), isTrue);
    });

    test('supports bouncing positions beyond a negative minimum extent', () {
      final pull = OldestHistoryPullController();

      expect(
        pull.updateBouncingPosition(
          _metrics(min: -600, max: 1400, pixels: -645),
        ),
        isFalse,
      );
      expect(
        pull.updateBouncingPosition(
          _metrics(min: -600, max: 1400, pixels: -653),
        ),
        isTrue,
      );
      expect(pull.distance, 53);
    });
  });

  group('chat scroll metrics', () {
    test('measures both edges when the minimum extent is negative', () {
      final metrics = _metrics(min: -600, max: 1400, pixels: -100);

      expect(distanceToOldest(metrics), 500);
      expect(distanceToLatest(metrics), 1500);
    });

    test('edge distances stop at zero during overscroll', () {
      final beforeOldest = _metrics(min: -600, max: 1400, pixels: -640);
      final afterLatest = _metrics(min: -600, max: 1400, pixels: 1440);

      expect(distanceToOldest(beforeOldest), 0);
      expect(distanceToLatest(afterLatest), 0);
    });

    test('near-edge checks include the threshold boundary', () {
      final nearOldest = _metrics(min: -500, max: 1500, pixels: -420);
      final nearLatest = _metrics(min: -500, max: 1500, pixels: 1470);

      expect(isNearOldest(nearOldest, threshold: 80), isTrue);
      expect(isNearOldest(nearOldest, threshold: 79), isFalse);
      expect(isNearLatest(nearLatest, threshold: 30), isTrue);
      expect(isNearLatest(nearLatest, threshold: 29), isFalse);
    });

    test('clamps offsets against the actual negative minimum', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: 0);

      expect(clampScrollOffset(metrics, -2000), -900);
      expect(clampScrollOffset(metrics, -225), -225);
      expect(clampScrollOffset(metrics, 2000), 1100);
    });

    test('maps offsets to fractions across the complete extent range', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: -400);

      expect(scrollFraction(metrics), closeTo(0.25, 0.0001));
      expect(scrollFraction(metrics, offset: 600), closeTo(0.75, 0.0001));
      expect(scrollFraction(metrics, offset: -2000), 0);
      expect(scrollFraction(metrics, offset: 2000), 1);
    });

    test('maps fractions to offsets across the complete extent range', () {
      final metrics = _metrics(min: -900, max: 1100, pixels: 0);

      expect(scrollOffsetForFraction(metrics, 0), -900);
      expect(scrollOffsetForFraction(metrics, 0.25), -400);
      expect(scrollOffsetForFraction(metrics, 0.5), 100);
      expect(scrollOffsetForFraction(metrics, 1), 1100);
      expect(scrollOffsetForFraction(metrics, -1), -900);
      expect(scrollOffsetForFraction(metrics, 2), 1100);
    });

    test('handles a range with no scrollable extent', () {
      final metrics = _metrics(min: -75, max: -75, pixels: -75);

      expect(clampScrollOffset(metrics, 100), -75);
      expect(scrollFraction(metrics), 0);
      expect(scrollOffsetForFraction(metrics, 0.75), -75);
      expect(isNearOldest(metrics, threshold: 0), isTrue);
      expect(isNearLatest(metrics, threshold: 0), isTrue);
    });

    test('pinned target offsets reserve the banner inset and clamp', () {
      final metrics = _metrics(min: -200, max: 800, pixels: 300);

      expect(
        pinnedMessageTargetScrollOffset(
          metrics,
          targetTop: 420,
          viewportTop: 100,
        ),
        548,
      );
      expect(
        pinnedMessageTargetScrollOffset(
          metrics,
          targetTop: -1000,
          viewportTop: 100,
        ),
        -200,
      );
      expect(
        pinnedMessageTargetScrollOffset(
          metrics,
          targetTop: 2000,
          viewportTop: 100,
        ),
        800,
      );
    });
  });

  testWidgets('pinned targets clear the floating banner in either direction', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: 700);
    final shortTargetKey = GlobalKey();
    final tallTargetKey = GlobalKey();
    const viewportKey = ValueKey('viewport');
    const bannerKey = ValueKey('pinned-banner');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: Stack(
              children: [
                SingleChildScrollView(
                  key: viewportKey,
                  controller: controller,
                  child: Column(
                    children: [
                      const SizedBox(height: 100),
                      SizedBox(key: shortTargetKey, height: 100),
                      const SizedBox(height: 800),
                      SizedBox(key: tallTargetKey, height: 620),
                      const SizedBox(height: 800),
                    ],
                  ),
                ),
                const Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: SizedBox(key: bannerKey, height: 48),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void> expectPinnedAlignment(GlobalKey targetKey) async {
      final viewportTop = tester.getTopLeft(find.byKey(viewportKey)).dy;
      final targetTop = tester.getTopLeft(find.byKey(targetKey)).dy;
      controller.jumpTo(
        pinnedMessageTargetScrollOffset(
          controller.position,
          targetTop: targetTop,
          viewportTop: viewportTop,
        ),
      );
      await tester.pump();

      final alignedViewportTop = tester.getTopLeft(find.byKey(viewportKey)).dy;
      final alignedTargetTop = tester.getTopLeft(find.byKey(targetKey)).dy;
      final bannerBottom = tester.getBottomLeft(find.byKey(bannerKey)).dy;
      expect(
        alignedTargetTop - alignedViewportTop,
        closeTo(pinnedMessageTargetTopInset, 0.01),
      );
      expect(alignedTargetTop, greaterThan(bannerBottom));
    }

    await expectPinnedAlignment(tallTargetKey);
    await expectPinnedAlignment(shortTargetKey);
    await expectPinnedAlignment(tallTargetKey);
  });
}

FixedScrollMetrics _metrics({
  required double min,
  required double max,
  required double pixels,
}) {
  return FixedScrollMetrics(
    minScrollExtent: min,
    maxScrollExtent: max,
    pixels: pixels,
    viewportDimension: 400,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
}
