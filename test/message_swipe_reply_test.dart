//
//  message_swipe_reply_test.dart
//
//  The row-level swipe that hands a message to the composer. Covers the two
//  halves a bubble-scoped gesture could not: the drag may start anywhere on the
//  row, and the row keeps out of the way of everything else that owns a
//  pointer — a scroller, a mouse selection, an armed text selection.
//

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/message_swipe_reply.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  const avatarKey = ValueKey('swipe-avatar');
  const bubbleKey = ValueKey('swipe-bubble');
  final replyGlyph = find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.icon == HeroAppIcons.reply,
  );

  group('travel damping', () {
    test('follows the finger to the resting limit', () {
      expect(messageSwipeReplyOffset(0), 0);
      expect(messageSwipeReplyOffset(-12), -12);
      expect(
        messageSwipeReplyOffset(-messageSwipeReplyRestingLimit),
        -messageSwipeReplyRestingLimit,
      );
    });

    test('resists past the resting limit and stops at the hard limit', () {
      final damped = messageSwipeReplyOffset(-92);
      expect(damped, closeTo(-(72 + 20 * messageSwipeReplyResistance), 0.001));
      expect(messageSwipeReplyOffset(-4000), -messageSwipeReplyHardLimit);
    });

    test('ignores a rightward travel', () {
      expect(messageSwipeReplyOffset(40), 0);
    });
  });

  group('commit decision', () {
    test('commits at the trigger', () {
      expect(
        messageSwipeReplyCommits(offset: -messageSwipeReplyTrigger),
        isTrue,
      );
      expect(
        messageSwipeReplyCommits(offset: -messageSwipeReplyTrigger + 1),
        isFalse,
      );
    });

    test('commits on a fast leftward flick short of the trigger', () {
      expect(
        messageSwipeReplyCommits(
          offset: -20,
          primaryVelocity: messageSwipeReplyFlickVelocity - 1,
        ),
        isTrue,
      );
      expect(
        messageSwipeReplyCommits(
          offset: -20,
          primaryVelocity: messageSwipeReplyFlickVelocity + 1,
        ),
        isFalse,
      );
    });

    test('ignores a rightward flick', () {
      expect(
        messageSwipeReplyCommits(offset: -20, primaryVelocity: 2000),
        isFalse,
      );
    });
  });

  /// One row: avatar, a narrow bubble, then empty trailing space — the shape
  /// that made a bubble-scoped gesture feel broken on a short message.
  Widget row() => SizedBox(
    width: 400,
    height: 60,
    child: Row(
      children: [
        Container(
          key: avatarKey,
          width: 38,
          height: 38,
          color: const Color(0xFF8899AA),
        ),
        const SizedBox(width: 8),
        Container(
          key: bubbleKey,
          width: 60,
          height: 40,
          color: const Color(0xFF45C4BE),
        ),
        const Spacer(),
      ],
    ),
  );

  Future<void> pumpRow(
    WidgetTester tester, {
    VoidCallback? onReply,
    bool swipeEnabled = true,
    MessageSwipeReplyController? controller,
    TargetPlatform platform = TargetPlatform.android,
    ScrollController? scrollController,
  }) async {
    final content = MessageSwipeReplyRow(
      onReply: onReply,
      swipeEnabled: swipeEnabled,
      controller: controller,
      child: row(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform, extensions: [AppColors.light]),
        home: Scaffold(
          body: scrollController == null
              ? content
              : ListView(
                  controller: scrollController,
                  children: [content, const SizedBox(height: 1200)],
                ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps a host that owns the travel — the shape `MessageBubble` uses, where
  /// a raw pointer path drives the controller instead of the gesture arena.
  Future<MessageSwipeReplyController> pumpHost(
    WidgetTester tester, {
    required VoidCallback onReply,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    MessageSwipeReplyController? controller;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform, extensions: [AppColors.light]),
        home: Scaffold(
          body: _ControllerHost(
            onReady: (value) => controller = value,
            onReply: onReply,
            child: row(),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller!;
  }

  /// Drags left in steps the way a finger arrives, and leaves the pointer down.
  Future<TestGesture> dragLeft(
    WidgetTester tester,
    Offset from, {
    required int steps,
    double step = -20,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final gesture = await tester.startGesture(from, kind: kind);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(step, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('a drag on the empty trailing space moves the row and replies', (
    tester,
  ) async {
    var replies = 0;
    await pumpRow(tester, onReply: () => replies++);
    final bubbleAtRest = tester.getRect(find.byKey(bubbleKey));

    // 300px right of the bubble: inside the row, far from any content.
    final gesture = await dragLeft(
      tester,
      Offset(bubbleAtRest.right + 200, bubbleAtRest.center.dy),
      steps: 6,
    );
    expect(
      tester.getRect(find.byKey(bubbleKey)).left,
      lessThan(bubbleAtRest.left),
      reason: 'the row follows the finger from anywhere on it',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(tester.getRect(find.byKey(bubbleKey)), bubbleAtRest);
  });

  testWidgets('a drag on the avatar moves the row and replies', (tester) async {
    var replies = 0;
    await pumpRow(tester, onReply: () => replies++);

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(avatarKey)),
      steps: 6,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 1);
  });

  testWidgets('the glyph is absent at rest and fades in with travel', (
    tester,
  ) async {
    await pumpRow(tester, onReply: () {});
    expect(replyGlyph, findsNothing);

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(bubbleKey)),
      steps: 1,
      step: -messageSwipeReplyGlyphFade / 2,
    );
    await tester.pump();
    expect(replyGlyph, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: replyGlyph, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, closeTo(0.5, 0.05));

    await gesture.moveBy(const Offset(-messageSwipeReplyGlyphFade, 0));
    await tester.pump();
    final full = tester.widget<Opacity>(
      find.ancestor(of: replyGlyph, matching: find.byType(Opacity)).first,
    );
    expect(full.opacity, 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(replyGlyph, findsNothing);
  });

  testWidgets('a release short of the trigger springs home without replying', (
    tester,
  ) async {
    var replies = 0;
    await pumpRow(tester, onReply: () => replies++);

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(bubbleKey)),
      steps: 1,
      step: -(messageSwipeReplyTrigger - 12),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 0);
    expect(replyGlyph, findsNothing);
  });

  testWidgets('a flick short of the trigger still commits', (tester) async {
    var replies = 0;
    void onReply() => replies++;
    final controller = await pumpHost(tester, onReply: onReply);

    // The pointer path a real flick takes: travel that stops short, then a
    // release speed past the flick threshold. `primaryVelocity` is fed in
    // because the automated binding reports 0 for every drag end — its pointer
    // events share one time stamp, so no velocity estimate survives.
    controller
      ..beginDrag()
      ..dragBy(-(messageSwipeReplyTrigger - 20));
    await tester.pump();
    expect(replyGlyph, findsOneWidget);

    controller.finish(
      onReply: onReply,
      primaryVelocity: messageSwipeReplyFlickVelocity - 100,
    );
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(controller.offset, 0);
  });

  testWidgets('crossing the trigger is felt once per attempt', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpRow(tester, onReply: () {});

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(bubbleKey)),
      steps: 6,
    );
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    // Dragging back out re-arms it, so a second attempt ticks again.
    await gesture.moveBy(const Offset(messageSwipeReplyTrigger * 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-messageSwipeReplyTrigger * 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(haptics.length, 2);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a desktop mouse drag is left to text selection', (tester) async {
    var replies = 0;
    await pumpRow(
      tester,
      onReply: () => replies++,
      platform: TargetPlatform.macOS,
    );
    final atRest = tester.getRect(find.byKey(bubbleKey));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(bubbleKey)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 0);
    expect(tester.getRect(find.byKey(bubbleKey)), atRest);
    expect(replyGlyph, findsNothing);
  });

  testWidgets('a host without a reply action gets no gesture at all', (
    tester,
  ) async {
    await pumpRow(tester);
    final atRest = tester.getRect(find.byKey(bubbleKey));

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(bubbleKey)),
      steps: 6,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(bubbleKey)), atRest);
    expect(replyGlyph, findsNothing);
  });

  testWidgets('a vertical drag stays with the scroller', (tester) async {
    var replies = 0;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await pumpRow(
      tester,
      onReply: () => replies++,
      scrollController: scrollController,
    );
    expect(scrollController.offset, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(bubbleKey)),
    );
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
    expect(replies, 0);
    expect(replyGlyph, findsNothing);
  });

  testWidgets('disabling the swipe mid-drag springs the row home', (
    tester,
  ) async {
    final armed = ValueNotifier<bool>(false);
    addTearDown(armed.dispose);
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.android,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: armed,
            builder: (context, selectionArmed, _) => MessageSwipeReplyRow(
              onReply: () => replies++,
              swipeEnabled: !selectionArmed,
              child: Container(
                key: bubbleKey,
                height: 40,
                color: const Color(0xFF45C4BE),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final atRest = tester.getRect(find.byKey(bubbleKey));

    final gesture = await dragLeft(
      tester,
      tester.getCenter(find.byKey(bubbleKey)),
      steps: 6,
    );
    expect(tester.getRect(find.byKey(bubbleKey)).left, lessThan(atRest.left));

    // An armed text selection takes the row over mid-drag.
    armed.value = true;
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 0);
    expect(tester.getRect(find.byKey(bubbleKey)), atRest);
  });

  testWidgets('a host-owned controller survives the row it drives', (
    tester,
  ) async {
    var replies = 0;
    void onReply() => replies++;
    final controller = await pumpHost(tester, onReply: onReply);

    // A raw pointer path drives the travel itself, the way the desktop touch
    // handler does.
    controller
      ..beginDrag()
      ..dragTo(-messageSwipeReplyTrigger - 4);
    await tester.pump();
    expect(replyGlyph, findsOneWidget);

    controller.finish(onReply: onReply, primaryVelocity: 0);
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(replyGlyph, findsNothing);
    expect(controller.offset, 0);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('a $platform raw touch swipe survives a host rebuild', (
      tester,
    ) async {
      var replies = 0;
      void onReply() => replies++;
      final controller = await pumpHost(
        tester,
        onReply: onReply,
        platform: platform,
      );
      controller
        ..beginDrag()
        ..dragTo(-messageSwipeReplyTrigger - 4);
      await tester.pump();

      // Live message updates may rebuild a desktop host while its raw pointer
      // handler still owns the touch drag. Mouse exclusion must not cancel it.
      tester.element(find.byType(_ControllerHost)).markNeedsBuild();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.offset, -messageSwipeReplyTrigger - 4);

      controller.finish(onReply: onReply, primaryVelocity: 0);
      await tester.pumpAndSettle();
      expect(replies, 1);
    });
  }
}

/// Stands in for a host that owns the travel and disposes it itself.
class _ControllerHost extends StatefulWidget {
  const _ControllerHost({
    required this.onReady,
    required this.onReply,
    required this.child,
  });

  final ValueChanged<MessageSwipeReplyController> onReady;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost>
    with SingleTickerProviderStateMixin {
  late final MessageSwipeReplyController _controller =
      MessageSwipeReplyController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MessageSwipeReplyRow(
    controller: _controller,
    onReply: widget.onReply,
    child: widget.child,
  );
}
