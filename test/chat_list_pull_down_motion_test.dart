import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/theme/theme_controller.dart';

void main() {
  test('native desktop makes pull-down archives an explicit top row', () {
    for (final platform in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final mode = effectiveChatListArchiveDisplayMode(
        ArchivedChatsDisplayMode.pullDown,
        platform: platform,
        isWeb: false,
      );

      expect(mode, ArchivedChatsDisplayMode.firstPosition);
      expect(mode.insertionIndex(chatCount: 8, visibleRows: 6), 0);
    }
  });

  test('touch platforms preserve pull-down archive behavior', () {
    for (final platform in const [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(
        effectiveChatListArchiveDisplayMode(
          ArchivedChatsDisplayMode.pullDown,
          platform: platform,
          isWeb: false,
        ),
        ArchivedChatsDisplayMode.pullDown,
      );
    }
  });

  test('web and explicit desktop archive modes are not overridden', () {
    expect(
      effectiveChatListArchiveDisplayMode(
        ArchivedChatsDisplayMode.pullDown,
        platform: TargetPlatform.macOS,
        isWeb: true,
      ),
      ArchivedChatsDisplayMode.pullDown,
    );

    for (final mode in const [
      ArchivedChatsDisplayMode.firstPosition,
      ArchivedChatsDisplayMode.nextPage,
      ArchivedChatsDisplayMode.hidden,
    ]) {
      expect(
        effectiveChatListArchiveDisplayMode(
          mode,
          platform: TargetPlatform.windows,
          isWeb: false,
        ),
        mode,
      );
    }
  });

  test('top overscroll offset ignores in-range scrolling', () {
    expect(chatListTopOverscrollOffset(24), 0);
    expect(chatListTopOverscrollOffset(0), 0);
    expect(chatListTopOverscrollOffset(-18.5), 18.5);
    expect(chatListTopOverscrollOffset(81.5, minScrollExtent: 100), 18.5);
  });

  test('pull-down archive thresholds preserve their exact boundaries', () {
    const rowHeight = 64.5;
    const revealThreshold = rowHeight * 0.45;
    const hideThreshold = rowHeight * 0.5;

    expect(
      chatListShouldRevealPullDownArchive(
        pullOffset: revealThreshold - 0.001,
        rowHeight: rowHeight,
      ),
      isFalse,
    );
    expect(
      chatListShouldRevealPullDownArchive(
        pullOffset: revealThreshold,
        rowHeight: rowHeight,
      ),
      isTrue,
    );
    expect(
      chatListShouldHidePullDownArchive(
        scrollPixels: hideThreshold,
        minScrollExtent: 0,
        rowHeight: rowHeight,
      ),
      isFalse,
    );
    expect(
      chatListShouldHidePullDownArchive(
        scrollPixels: hideThreshold + 0.001,
        minScrollExtent: 0,
        rowHeight: rowHeight,
      ),
      isTrue,
    );
  });

  testWidgets('pull-down pin stays fixed through drag and bounce', (
    tester,
  ) async {
    final controller = ScrollController();
    final archiveVisible = ValueNotifier(false);
    const rowHeight = 64.5;
    const searchKey = ValueKey('pinned-search');
    const assistantKey = ValueKey('pinned-assistant');

    void updateArchiveVisibility() {
      final positions = controller.positions;
      if (positions.length != 1) return;
      final position = positions.single;
      if (!position.hasContentDimensions) return;
      final pullOffset = chatListTopOverscrollOffset(
        position.pixels,
        minScrollExtent: position.minScrollExtent,
      );
      if (chatListShouldRevealPullDownArchive(
        pullOffset: pullOffset,
        rowHeight: rowHeight,
      )) {
        archiveVisible.value = true;
      }
    }

    controller.addListener(updateArchiveVisibility);
    addTearDown(() {
      controller.removeListener(updateArchiveVisibility);
      controller.dispose();
      archiveVisible.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ListView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                ChatListTopOverscrollPin(
                  controller: controller,
                  child: const SizedBox(
                    key: searchKey,
                    height: 50,
                    width: double.infinity,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: archiveVisible,
                  builder: (context, visible, child) =>
                      ChatListPullDownArchiveSlot(
                        controller: controller,
                        rowHeight: rowHeight,
                        visible: visible,
                        child: const SizedBox(
                          key: assistantKey,
                          width: double.infinity,
                        ),
                      ),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      ),
    );

    final initialSearchY = tester.getTopLeft(find.byKey(searchKey)).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(searchKey)),
    );
    final observedPixels = <double>[];
    final assistantYs = <double>[];

    for (final delta in const [16.0, 20.0, 24.0, 28.0, 32.0, 36.0]) {
      await gesture.moveBy(Offset(0, delta));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.position.pixels, lessThan(0));
      observedPixels.add(controller.position.pixels);
      expect(
        tester.getTopLeft(find.byKey(searchKey)).dy,
        moreOrLessEquals(initialSearchY, epsilon: 0.01),
      );
      if (find.byKey(assistantKey).evaluate().isNotEmpty) {
        assistantYs.add(tester.getTopLeft(find.byKey(assistantKey)).dy);
      }
    }

    await gesture.up();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(find.byKey(searchKey)).dy,
        moreOrLessEquals(initialSearchY, epsilon: 0.01),
      );
      if (find.byKey(assistantKey).evaluate().isNotEmpty) {
        assistantYs.add(tester.getTopLeft(find.byKey(assistantKey)).dy);
      }
    }
    await tester.pumpAndSettle();

    expect(observedPixels.toSet().length, greaterThanOrEqualTo(3));
    expect(assistantYs.length, greaterThanOrEqualTo(3));
    expect(
      assistantYs.reduce(math.max) - assistantYs.reduce(math.min),
      lessThanOrEqualTo(0.01),
    );
    expect(controller.position.pixels, moreOrLessEquals(0, epsilon: 0.01));
    expect(
      tester.getTopLeft(find.byKey(searchKey)).dy,
      moreOrLessEquals(initialSearchY, epsilon: 0.01),
    );
  });
}
