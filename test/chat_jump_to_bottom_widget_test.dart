import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_frame_scheduler.dart';

void main() {
  testWidgets('idle return schedules a frame for its post-frame callback', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_JumpToBottomHarnessState>();
    await tester.pumpWidget(_testApp(_JumpToBottomHarness(key: harnessKey)));

    final harness = harnessKey.currentState!;
    harness.jumpToLatestFraction(0.25);
    await tester.pumpAndSettle();
    final pixelsBeforeTap = harness.controller.position.pixels;

    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tap(find.byKey(_JumpToBottomHarness.jumpButtonKey));

    expect(harness.returnFrameRequests, 1);
    expect(harness.returnCallbacksRun, 0);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(harness.controller.position.pixels, pixelsBeforeTap);

    // The requested frame runs the post-frame callback and starts the driven
    // scroll. The following frame must then make visible progress.
    await tester.pump();
    expect(harness.returnCallbacksRun, 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.pixels, greaterThan(pixelsBeforeTap));

    await tester.pumpAndSettle();
    _expectAtLoadedBottom(harness.controller);
  });

  testWidgets('explicit return interrupts a ballistic fling', (tester) async {
    final harnessKey = GlobalKey<_JumpToBottomHarnessState>();
    await tester.pumpWidget(_testApp(_JumpToBottomHarness(key: harnessKey)));

    final harness = harnessKey.currentState!;
    harness.jumpToLatestFraction(0.65);
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(_JumpToBottomHarness.scrollViewKey),
      const Offset(0, 260),
      2400,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.isScrollingNotifier.value, isTrue);

    final pixelsBeforeBallisticTick = harness.controller.position.pixels;
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      harness.controller.position.pixels,
      lessThan(pixelsBeforeBallisticTick),
    );

    await tester.tap(find.byKey(_JumpToBottomHarness.jumpButtonKey));
    final pixelsAtTap = harness.controller.position.pixels;

    // The explicit action stops the old activity synchronously. Its new
    // driven activity begins in the deliberately requested post-frame phase.
    expect(harness.controller.position.isScrollingNotifier.value, isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.pixels, greaterThan(pixelsAtTap));

    await tester.pumpAndSettle();
    _expectAtLoadedBottom(harness.controller);
  });

  testWidgets('a new transcript drag cancels an in-flight explicit return', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_JumpToBottomHarnessState>();
    await tester.pumpWidget(_testApp(_JumpToBottomHarness(key: harnessKey)));

    final harness = harnessKey.currentState!;
    harness.jumpToLatestFraction(0.20);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_JumpToBottomHarness.jumpButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(harness.controller.position.isScrollingNotifier.value, isTrue);
    final pixelsDuringReturn = harness.controller.position.pixels;

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(_JumpToBottomHarness.scrollViewKey)),
      pointer: 7,
    );
    expect(harness.pointerCancellations, 1);

    await drag.moveBy(const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.pixels, lessThan(pixelsDuringReturn));
    await drag.up();

    await tester.pumpAndSettle();
    expect(
      harness.controller.position.maxScrollExtent -
          harness.controller.position.pixels,
      greaterThan(100),
      reason: 'the cancelled return must not reclaim the user-controlled view',
    );
  });
}

Widget _testApp(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 320, height: 420, child: child)),
  );
}

void _expectAtLoadedBottom(ScrollController controller) {
  expect(controller.position.outOfRange, isFalse);
  expect(
    controller.position.pixels,
    closeTo(controller.position.maxScrollExtent, 0.5),
  );
  expect(controller.position.isScrollingNotifier.value, isFalse);
}

class _JumpToBottomHarness extends StatefulWidget {
  const _JumpToBottomHarness({super.key});

  static const scrollViewKey = ValueKey('jump-bottom-scroll-view');
  static const jumpButtonKey = ValueKey('jump-bottom-button');

  @override
  State<_JumpToBottomHarness> createState() => _JumpToBottomHarnessState();
}

class _JumpToBottomHarnessState extends State<_JumpToBottomHarness> {
  final ScrollController controller = ScrollController();
  final GlobalKey _latestSliverKey = GlobalKey();

  int _returnGeneration = 0;
  int _scheduledGeneration = 0;
  bool _returnFrameScheduled = false;

  int returnFrameRequests = 0;
  int returnCallbacksRun = 0;
  int pointerCancellations = 0;

  void jumpToLatestFraction(double fraction) {
    final position = controller.position;
    controller.jumpTo(position.maxScrollExtent * fraction);
  }

  void _requestLoadedBottom() {
    final generation = ++_returnGeneration;
    _scheduledGeneration = generation;
    _stopActiveScroll();
    if (_returnFrameScheduled) return;

    _returnFrameScheduled = true;
    returnFrameRequests++;
    scheduleChatPostFrame(() {
      _returnFrameScheduled = false;
      final scheduledGeneration = _scheduledGeneration;
      if (!mounted ||
          scheduledGeneration != _returnGeneration ||
          !controller.hasClients) {
        return;
      }
      returnCallbacksRun++;
      final target = controller.position.maxScrollExtent;
      if ((target - controller.position.pixels).abs() <= 0.5) return;
      unawaited(
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _cancelReturnForPointer(PointerDownEvent event) {
    pointerCancellations++;
    ++_returnGeneration;
    _stopActiveScroll();
  }

  void _stopActiveScroll() {
    if (!controller.hasClients ||
        !controller.position.isScrollingNotifier.value) {
      return;
    }
    controller.jumpTo(controller.position.pixels);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _cancelReturnForPointer,
            child: CustomScrollView(
              key: _JumpToBottomHarness.scrollViewKey,
              controller: controller,
              center: _latestSliverKey,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverList.builder(
                  itemCount: 16,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 64, child: Text('older-$index')),
                ),
                SliverList.builder(
                  key: _latestSliverKey,
                  itemCount: 80,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 64, child: Text('latest-$index')),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: GestureDetector(
            key: _JumpToBottomHarness.jumpButtonKey,
            behavior: HitTestBehavior.opaque,
            onTap: _requestLoadedBottom,
            child: const ColoredBox(
              color: Color(0xFFE8E8E8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Text('bottom')),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
